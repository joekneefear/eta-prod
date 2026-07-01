use std::collections::HashMap;
use std::io::Write;
use std::path::Path;
use rust_stdf::stdf_file::StdfReader;
// Use explicit imports matching rust-stdf 
use rust_stdf::{StdfRecord, FAR, MIR, MRR, TSR, HBR, SBR, PCR, PIR}; 
use quick_xml::events::{BytesDecl, BytesEnd, BytesStart, Event};
use quick_xml::Writer;
use crate::models::OutputMeta;

// Struct to hold extra metadata for tests found in PTRs (Limits, Units)
#[derive(Default, Clone)]
struct TestMetadata {
    units: Option<String>,
    lo_limit: Option<f32>,
    hi_limit: Option<f32>,
    lo_spec: Option<f32>,
    hi_spec: Option<f32>,
}

// Struct to hold summary data collected in Pass 1
#[derive(Default)]
struct SummaryInfo {
    far: Option<FAR>,
    mir: Option<MIR>,
    mrr: Option<MRR>,
    tsrs: Vec<TSR>,
    hbrs: Vec<HBR>,
    sbrs: Vec<SBR>,
    pcrs: Vec<PCR>,
    // Map TestNum to (Id, TestName) for linkage and fallback
    test_map: HashMap<u32, usize>,
    // Map TestNum to metadata collected from PTR
    test_meta: HashMap<u32, TestMetadata>,
}

struct MeasBuffer {
    val: String,
    pf: String,
    pm_id: usize,
}

pub fn process_stdf_to_text<W: Write>(path: &Path, original_filename: &str, writer: W) -> anyhow::Result<OutputMeta> {
    // --- PASS 1: Collect Context & Summaries ---
    let mut summary = SummaryInfo::default();
    
    {
        let mut reader = StdfReader::new(path).map_err(|e| anyhow::anyhow!("Pass 1 Init Error: {}", e))?;
        for record in reader.get_record_iter() {
             if let Ok(record) = record {
                match record {
                    StdfRecord::FAR(r) => summary.far = Some(r),
                    StdfRecord::MIR(r) => summary.mir = Some(r),
                    StdfRecord::MRR(r) => summary.mrr = Some(r),
                    StdfRecord::TSR(r) => summary.tsrs.push(r),
                    StdfRecord::HBR(r) => summary.hbrs.push(r),
                    StdfRecord::SBR(r) => summary.sbrs.push(r),
                    StdfRecord::PCR(r) => summary.pcrs.push(r),
                    StdfRecord::PTR(r) => {
                        // Capture metadata from the first PTR seen for a given TestNum?
                        // Or overwrite? Usually limits are constant. 
                        // We check if we already have it to avoid re-allocation/checking every time if optimization needed.
                        // But HashMap insert is fast enough.
                        summary.test_meta.entry(r.test_num).or_insert_with(|| TestMetadata {
                            units: r.units,
                            lo_limit: r.lo_limit,
                            hi_limit: r.hi_limit,
                            lo_spec: r.lo_spec,
                            hi_spec: r.hi_spec,
                        });
                    }
                    _ => {}
                }
             }
        }
    }

    // Assign IDs to TSRs for referencing
    for (i, tsr) in summary.tsrs.iter().enumerate() {
        summary.test_map.insert(tsr.test_num, i + 1);
    }

    let mut output_meta = OutputMeta::empty();
    if let Some(mir) = &summary.mir {
        output_meta.tester = mir.tstr_typ.clone();
        output_meta.platform = mir.node_nam.clone();
        output_meta.session = mir.setup_t.to_string();
    }

    // --- PASS 2: Write XML ---
    let mut xml_writer = Writer::new(writer);
    xml_writer.write_event(Event::Decl(BytesDecl::new("1.0", Some("ISO-8859-1"), None)))?;
    
    let root = BytesStart::new("Xml");
    xml_writer.write_event(Event::Start(root))?;

    // <File>
    let mut file_elem = BytesStart::new("File");
    file_elem.push_attribute(("FileName", original_filename));
    
    if let Some(far) = &summary.far {
        file_elem.push_attribute(("CPUType", far.cpu_type.to_string().as_str()));
        file_elem.push_attribute(("STDFVersion", far.stdf_ver.to_string().as_str()));
    }
    xml_writer.write_event(Event::Start(file_elem))?;

    // <Lot>
    let mut lot_elem = BytesStart::new("Lot");
    if let Some(mir) = &summary.mir {
        lot_elem.push_attribute(("LotId", mir.lot_id.as_str()));
        lot_elem.push_attribute(("PartType", mir.part_typ.as_str()));
        lot_elem.push_attribute(("JobName", mir.job_nam.as_str()));
        lot_elem.push_attribute(("TesterType", mir.tstr_typ.as_str()));
        lot_elem.push_attribute(("NodeName", mir.node_nam.as_str()));
        lot_elem.push_attribute(("OperatorName", mir.oper_nam.as_str()));
        lot_elem.push_attribute(("ExecType", mir.exec_typ.as_str()));
        lot_elem.push_attribute(("ExecVersion", mir.exec_ver.as_str()));
        lot_elem.push_attribute(("TestCode", mir.test_cod.as_str()));
        lot_elem.push_attribute(("ModeCode", mir.mode_cod.to_string().as_str())); // Fix char as_str()
        lot_elem.push_attribute(("SublotId", mir.sblot_id.as_str()));
        lot_elem.push_attribute(("SetupTime", mir.setup_t.to_string().as_str()));
        lot_elem.push_attribute(("StartTime", mir.start_t.to_string().as_str()));
        lot_elem.push_attribute(("TesterSerial", mir.stat_num.to_string().as_str()));
    }
    if let Some(mrr) = &summary.mrr {
        lot_elem.push_attribute(("FinishTime", mrr.finish_t.to_string().as_str()));
    }
    xml_writer.write_event(Event::Start(lot_elem))?;

    // <Parameters> (From TSRs + Metadata)
    xml_writer.write_event(Event::Start(BytesStart::new("Parameters")))?;
    for (i, tsr) in summary.tsrs.iter().enumerate() {
        let mut p = BytesStart::new("Param");
        p.push_attribute(("Id", (i + 1).to_string().as_str()));
        p.push_attribute(("TestNumber", tsr.test_num.to_string().as_str()));
        p.push_attribute(("TestName", tsr.test_nam.as_str()));
        p.push_attribute(("TestDescription", tsr.test_nam.as_str()));
        p.push_attribute(("TestType", tsr.test_typ.to_string().as_str()));
        
        // Limits & Scales from PTR metadata if available
        if let Some(meta) = summary.test_meta.get(&tsr.test_num) {
            if let Some(hi) = meta.hi_limit { p.push_attribute(("HighLimit", hi.to_string().as_str())); }
            if let Some(lo) = meta.lo_limit { p.push_attribute(("LowLimit", lo.to_string().as_str())); }
            if let Some(spec_hi) = meta.hi_spec { p.push_attribute(("HighSpecLimit", spec_hi.to_string().as_str())); }
            if let Some(spec_lo) = meta.lo_spec { p.push_attribute(("LowSpecLimit", spec_lo.to_string().as_str())); }
            if let Some(units) = &meta.units {
                if !units.is_empty() { p.push_attribute(("Units", units.as_str())); }
            }
        }
        
        xml_writer.write_event(Event::Empty(p))?;
    }
    xml_writer.write_event(Event::End(BytesEnd::new("Parameters")))?;

    // <SummaryData>
    xml_writer.write_event(Event::Start(BytesStart::new("SummaryData")))?;
    
    // <PartInfo> (From PCR)
    xml_writer.write_event(Event::Start(BytesStart::new("PartInfo")))?;
    for pcr in &summary.pcrs {
         let mut p = BytesStart::new("Part");
         p.push_attribute(("Head", pcr.head_num.to_string().as_str()));
         p.push_attribute(("Site", pcr.site_num.to_string().as_str()));
         p.push_attribute(("PartCount", pcr.part_cnt.to_string().as_str()));
         p.push_attribute(("GoodCount", pcr.good_cnt.to_string().as_str()));
         p.push_attribute(("RetestCount", pcr.rtst_cnt.to_string().as_str()));
         p.push_attribute(("AbortCount", pcr.abrt_cnt.to_string().as_str()));
         p.push_attribute(("FunctionalCount", pcr.func_cnt.to_string().as_str()));
         xml_writer.write_event(Event::Empty(p))?;
    }
    xml_writer.write_event(Event::End(BytesEnd::new("PartInfo")))?;

    // <BinInfo> (HBR/SBR)
    xml_writer.write_event(Event::Start(BytesStart::new("BinInfo")))?;
    for hbr in &summary.hbrs {
        let mut b = BytesStart::new("Bin");
        b.push_attribute(("Type", "Hardware"));
        b.push_attribute(("Head", hbr.head_num.to_string().as_str()));
        b.push_attribute(("Site", hbr.site_num.to_string().as_str()));
        b.push_attribute(("Number", hbr.hbin_num.to_string().as_str()));
        b.push_attribute(("Count", hbr.hbin_cnt.to_string().as_str()));
        let name_str = hbr.hbin_nam.as_str();
        b.push_attribute(("Name", name_str));
        b.push_attribute(("PassFail", if hbr.hbin_pf == 'P' { "P" } else { "F" }));
        xml_writer.write_event(Event::Empty(b))?;
    }
    for sbr in &summary.sbrs {
        let mut b = BytesStart::new("Bin");
        b.push_attribute(("Type", "Software"));
        b.push_attribute(("Head", sbr.head_num.to_string().as_str()));
        b.push_attribute(("Site", sbr.site_num.to_string().as_str()));
        b.push_attribute(("Number", sbr.sbin_num.to_string().as_str()));
        b.push_attribute(("Count", sbr.sbin_cnt.to_string().as_str()));
        let name_str = sbr.sbin_nam.as_str();
        b.push_attribute(("Name", name_str));
        b.push_attribute(("PassFail", if sbr.sbin_pf == 'P' { "P" } else { "F" }));
        xml_writer.write_event(Event::Empty(b))?;
    }
    xml_writer.write_event(Event::End(BytesEnd::new("BinInfo")))?;
    
    // <TestInfo> (TSR stats)
    xml_writer.write_event(Event::Start(BytesStart::new("TestInfo")))?;
    for (i, tsr) in summary.tsrs.iter().enumerate() {
        let mut t = BytesStart::new("Test");
        t.push_attribute(("PmId", (i + 1).to_string().as_str()));
        t.push_attribute(("Head", tsr.head_num.to_string().as_str()));
        t.push_attribute(("Site", tsr.site_num.to_string().as_str()));
        t.push_attribute(("ExecutionCount", tsr.exec_cnt.to_string().as_str()));
        t.push_attribute(("FailCount", tsr.fail_cnt.to_string().as_str()));
        t.push_attribute(("AlarmCount", tsr.alrm_cnt.to_string().as_str()));
        
        t.push_attribute(("TestMinValue", tsr.test_min.to_string().as_str()));
        t.push_attribute(("TestMaxValue", tsr.test_max.to_string().as_str()));
        
        // Calculate Mean = Sum / ExecCnt
        let mut mean_val = 0.0;
        let sum_val = tsr.tst_sums; // Field is tst_sums in rust-stdf
        if tsr.exec_cnt > 0 {
             mean_val = sum_val / (tsr.exec_cnt as f32);
        }
        t.push_attribute(("TestAvgTime", mean_val.to_string().as_str())); 
        
        t.push_attribute(("TestSumValue", sum_val.to_string().as_str()));
        t.push_attribute(("TestSumSqrValue", tsr.tst_sqrs.to_string().as_str())); // Field is tst_sqrs
        
        xml_writer.write_event(Event::Empty(t))?;
    }
    xml_writer.write_event(Event::End(BytesEnd::new("TestInfo")))?;

    xml_writer.write_event(Event::End(BytesEnd::new("SummaryData")))?;

    // <ParametricData>
    xml_writer.write_event(Event::Start(BytesStart::new("ParametricData")))?;

    // --- Pass 2 Reading ---
    let mut reader = StdfReader::new(path).map_err(|e| anyhow::anyhow!("Pass 2 Init Error: {}", e))?;
    let mut current_unit_pir: Option<PIR> = None;
    let mut current_unit_meas: Vec<MeasBuffer> = Vec::with_capacity(100);
    let mut part_index = 0;

    for record in reader.get_record_iter() {
        if let Ok(record) = record {
            match record {
                StdfRecord::PIR(pir) => {
                    current_unit_pir = Some(pir);
                    current_unit_meas.clear();
                    part_index += 1;
                },
                StdfRecord::PTR(ptr) => {
                    if let Some(id) = summary.test_map.get(&ptr.test_num) {
                        let pf = if (ptr.test_flg[0] & 0x80) != 0 { "F" } else { "P" };
                        let val = ptr.result.to_string();
                        current_unit_meas.push(MeasBuffer { val, pf: pf.to_string(), pm_id: *id });
                    }
                },
                StdfRecord::FTR(ftr) => {
                     if let Some(id) = summary.test_map.get(&ftr.test_num) {
                        let pf = if (ftr.test_flg[0] & 0x80) != 0 { "F" } else { "P" };
                        current_unit_meas.push(MeasBuffer { val: "0.0".to_string(), pf: pf.to_string(), pm_id: *id });
                     }
                },
                StdfRecord::PRR(prr) => {
                    if let Some(_pir) = &current_unit_pir {
                        let mut u = BytesStart::new("Unit");
                        u.push_attribute(("Site", prr.site_num.to_string().as_str()));
                        u.push_attribute(("Head", prr.head_num.to_string().as_str()));
                        u.push_attribute(("TestCount", current_unit_meas.len().to_string().as_str()));
                        u.push_attribute(("HardBin", prr.hard_bin.to_string().as_str()));
                        u.push_attribute(("SoftBin", prr.soft_bin.to_string().as_str()));
                        u.push_attribute(("X", prr.x_coord.to_string().as_str()));
                        u.push_attribute(("Y", prr.y_coord.to_string().as_str()));
                        u.push_attribute(("PartId", prr.part_id.as_str()));
                        u.push_attribute(("PartIndex", part_index.to_string().as_str()));
                        
                        xml_writer.write_event(Event::Start(u))?;
                        
                        for m in &current_unit_meas {
                            let mut me = BytesStart::new("Meas");
                            me.push_attribute(("Val", m.val.as_str()));
                            me.push_attribute(("PF", m.pf.as_str()));
                            me.push_attribute(("PmId", m.pm_id.to_string().as_str()));
                            xml_writer.write_event(Event::Empty(me))?;
                        }
                        
                        xml_writer.write_event(Event::End(BytesEnd::new("Unit")))?;
                    }
                    current_unit_pir = None;
                    current_unit_meas.clear();
                },
                _ => {}
            }
        }
    }

    xml_writer.write_event(Event::End(BytesEnd::new("ParametricData")))?;
    xml_writer.write_event(Event::End(BytesEnd::new("Lot")))?;
    xml_writer.write_event(Event::End(BytesEnd::new("File")))?;
    xml_writer.write_event(Event::End(BytesEnd::new("Xml")))?;

    Ok(output_meta)
}
