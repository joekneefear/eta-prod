use std::io::{Write, BufWriter};
use std::path::Path;
use std::collections::HashMap;
use rust_stdf::stdf_file::StdfReader;
use rust_stdf::StdfRecord;
use quick_xml::events::{Event, BytesStart, BytesEnd};
use quick_xml::Writer;
use crate::models::OutputMeta;

/// TestInfo consolidation structure
/// Caches test metadata from TSR records for use with PTR/FTR/MPR
#[derive(Clone, Debug)]
#[allow(dead_code)]
struct TestMetadata {
    test_num: u32,
    test_name: String,
    head_num: u8,
}

/// High-performance STDF to SXML translator
/// Uses buffered I/O and optimized processing for maximum throughput
pub fn process_stdf_stream<W: Write>(path: &Path, original_filename: &str, writer: W) -> anyhow::Result<OutputMeta> {
    // Wrap with BufWriter for faster I/O (critical for performance)
    let buf_writer = BufWriter::with_capacity(1024 * 1024, writer); // 1MB buffer
    let mut xml_writer = Writer::new_with_indent(buf_writer, b'\n', 0);

    // Write XML declaration
    xml_writer.write_event(Event::Decl(quick_xml::events::BytesDecl::new("1.0", Some("UTF-8"), None)))?;

    // Root wrapper element (Xml)
    xml_writer.write_event(Event::Start(BytesStart::new("Xml")))?;

    let mut stdf_reader = StdfReader::new(path).map_err(|e| anyhow::anyhow!("{}", e))?;

    // OPTIMIZATION: Single-pass record processing with early detection
    // Collect records but process immediately for quick sections
    let records: Vec<_> = match stdf_reader.get_record_iter().collect::<Result<Vec<_>, _>>() {
        Ok(v) => v,
        Err(e) => {
            // Log contextual info to help diagnose truncated/corrupt STDF files
            tracing::error!("STDF parse error for file {}: {}", path.display(), e);
            if let Ok(meta) = std::fs::metadata(path) {
                tracing::error!("STDF file size: {} bytes", meta.len());
            }
            // Try to read a small head of the file for debugging
            match std::fs::File::open(path) {
                Ok(mut f) => {
                    use std::io::Read;
                    let mut buf = [0u8; 256];
                    if let Ok(n) = f.read(&mut buf) {
                        let snippet = buf[..n].iter().map(|b| format!("{:02x}", b)).collect::<Vec<_>>().join(" ");
                        tracing::error!("STDF head ({} bytes): {}", n, snippet);
                    }
                }
                Err(err) => tracing::error!("Failed to open STDF file for debug read: {}", err),
            }
            return Err(anyhow::anyhow!("{}", e));
        }
    };

    // Build TestInfo cache only if needed (lazy evaluation)
    let mut test_info_cache: HashMap<(u32, u8), TestMetadata> = HashMap::with_capacity(1000); // Pre-allocate for typical 1000+ tests
    let mut has_audits = false;
    let mut has_gdrs = false;
    let mut far_cpu_type = String::from("0");
    let mut far_stdf_ver = String::from("0");
    let mut output_meta = OutputMeta::empty();

    // OPTIMIZATION: First pass with early exits and quick lookups
    // Pre-allocate common string constants to avoid repeated allocations
    const PASS_STR: &str = "P";
    const FAIL_STR: &str = "F";

    for record in &records {
        match record {
            StdfRecord::ATR(_) => has_audits = true,
            StdfRecord::GDR(_) => has_gdrs = true,
            StdfRecord::TSR(tsr) => {
                // Only insert if test name is non-empty (filter out placeholder TSRs)
                if !tsr.test_nam.is_empty() {
                    test_info_cache.insert(
                        (tsr.test_num, tsr.head_num),
                        TestMetadata {
                            test_num: tsr.test_num,
                            test_name: tsr.test_nam.clone(),
                            head_num: tsr.head_num,
                        }
                    );
                }
            }
            StdfRecord::FAR(far) => {
                far_cpu_type = far.cpu_type.to_string();
                far_stdf_ver = far.stdf_ver.to_string();
            }
            StdfRecord::MIR(mir) => {
                output_meta.tester = mir.tstr_typ.clone();
                output_meta.platform = mir.node_nam.clone();
                output_meta.session = mir.setup_t.to_string();
            }
            _ => {}
        }
    }

    // Process File element and Audits section
    let mut file_elem = BytesStart::new("File");
    file_elem.push_attribute(("FileName", original_filename));
    file_elem.push_attribute(("CPUType", far_cpu_type.as_str()));
    file_elem.push_attribute(("STDFVersion", far_stdf_ver.as_str()));

    xml_writer.write_event(Event::Start(file_elem))?;

    // Emit Audits section if present
    if has_audits {
        xml_writer.write_event(Event::Start(BytesStart::new("Audits")))?;
        for record in &records {
            if let StdfRecord::ATR(atr) = record {
                let mut audit = BytesStart::new("Audit");
                audit.push_attribute(("CMDLine", atr.cmd_line.as_str()));
                audit.push_attribute(("ModificationTime", atr.mod_tim.to_string().as_str()));
                xml_writer.write_event(Event::Empty(audit))?;
            }
        }
        xml_writer.write_event(Event::End(BytesEnd::new("Audits")))?;
    }

    // Main processing: Lot -> Wafers -> Units -> Tests hierarchy
    let mut in_lot = false;
    let mut in_wafers = false;
    let mut in_wafer = false;
    let mut in_units = false;
    let mut in_unit = false;
    let mut sites_emitted = false;
    let mut pins_emitted = false;

    for record in &records {
        match record {
            StdfRecord::MIR(mir) => {
                // Close any previous structures
                close_all_open_tags(&mut xml_writer, &mut in_unit, &mut in_units, &mut in_wafer, &mut in_wafers, &mut in_lot)?;

                // Emit Lot element
                let mut lot = BytesStart::new("Lot");
                lot.push_attribute(("PartType", mir.part_typ.as_str()));
                lot.push_attribute(("OperatorName", mir.oper_nam.as_str()));
                lot.push_attribute(("TesterType", mir.tstr_typ.as_str()));
                lot.push_attribute(("NodeName", mir.node_nam.as_str()));
                lot.push_attribute(("TestCode", mir.test_cod.as_str()));
                lot.push_attribute(("StartTime", format_timestamp(mir.setup_t).as_str()));
                lot.push_attribute(("JobName", mir.job_nam.as_str()));
                lot.push_attribute(("FloorId", mir.floor_id.as_str()));
                lot.push_attribute(("JobRevision", mir.job_rev.as_str()));
                lot.push_attribute(("LotId", mir.lot_id.as_str()));
                lot.push_attribute(("TestTemperature", mir.tst_temp.to_string().as_str()));
                lot.push_attribute(("SublotId", mir.sblot_id.as_str()));
                lot.push_attribute(("SetupTime", format_timestamp(mir.setup_t).as_str()));
                lot.push_attribute(("AUXFile", mir.aux_file.as_str()));

                xml_writer.write_event(Event::Start(lot))?;
                in_lot = true;
                sites_emitted = false;
                pins_emitted = false;
            }
            StdfRecord::WIR(wir) => {
                // Emit Sites section once per Lot (before first wafer)
                if in_lot && !sites_emitted && has_gdrs {
                    emit_sites(&mut xml_writer, &records)?;
                    sites_emitted = true;
                }

                // Emit Pins section once per Lot (before first wafer)
                if in_lot && !pins_emitted && has_gdrs {
                    emit_pins(&mut xml_writer, &records)?;
                    pins_emitted = true;
                }

                // Start Wafers section if needed
                if in_lot && !in_wafers {
                    xml_writer.write_event(Event::Start(BytesStart::new("Wafers")))?;
                    in_wafers = true;
                }

                // Close previous Unit and Wafer
                if in_unit {
                    xml_writer.write_event(Event::End(BytesEnd::new("Unit")))?;
                    in_unit = false;
                }
                if in_wafer {
                    xml_writer.write_event(Event::End(BytesEnd::new("Wafer")))?;
                }

                // Emit Wafer element
                let mut wafer = BytesStart::new("Wafer");
                wafer.push_attribute(("WaferId", wir.wafer_id.as_str()));
                wafer.push_attribute(("StartTime", format_timestamp(wir.start_t).as_str()));

                xml_writer.write_event(Event::Start(wafer))?;
                in_wafer = true;
                in_units = false;
            }
            StdfRecord::WRR(_wrr) => {
                // Close Unit and Wafer on WRR
                if in_unit {
                    xml_writer.write_event(Event::End(BytesEnd::new("Unit")))?;
                    in_unit = false;
                }
                if in_units {
                    xml_writer.write_event(Event::End(BytesEnd::new("Units")))?;
                    in_units = false;
                }
                if in_wafer {
                    xml_writer.write_event(Event::End(BytesEnd::new("Wafer")))?;
                    in_wafer = false;
                }
            }
            StdfRecord::PIR(pir) => {
                // Start Units section if needed
                if in_wafer && !in_units {
                    xml_writer.write_event(Event::Start(BytesStart::new("Units")))?;
                    in_units = true;
                }

                // Close previous Unit
                if in_unit {
                    xml_writer.write_event(Event::End(BytesEnd::new("Unit")))?;
                }

                // Emit Unit element
                let mut unit = BytesStart::new("Unit");
                unit.push_attribute(("Head", pir.head_num.to_string().as_str()));
                unit.push_attribute(("Site", pir.site_num.to_string().as_str()));

                xml_writer.write_event(Event::Start(unit))?;
                in_unit = true;
            }
            StdfRecord::PTR(ptr) => {
                if in_unit {
                    let mut test = BytesStart::new("Test");
                    test.push_attribute(("TestNum", ptr.test_num.to_string().as_str()));

                    // Use TestInfo consolidation: lookup cached test name from TSR
                    let test_name = if let Some(test_meta) = test_info_cache.get(&(ptr.test_num, ptr.head_num)) {
                        test_meta.test_name.as_str()
                    } else {
                        ptr.test_txt.as_str()
                    };
                    test.push_attribute(("TestName", test_name));
                    test.push_attribute(("Value", ptr.result.to_string().as_str()));
                    // OPTIMIZATION: Use pre-allocated string constants instead of inline conditionals
                    test.push_attribute(("PF", if ptr.test_flg[0] & 0x80 != 0 { FAIL_STR } else { PASS_STR }));

                    if let Some(lo_limit) = ptr.lo_limit {
                        test.push_attribute(("Min", lo_limit.to_string().as_str()));
                    }
                    if let Some(hi_limit) = ptr.hi_limit {
                        test.push_attribute(("Max", hi_limit.to_string().as_str()));
                    }
                    if let Some(units_str) = &ptr.units {
                        test.push_attribute(("Units", units_str.as_str()));
                    }

                    xml_writer.write_event(Event::Empty(test))?;
                }
            }
            StdfRecord::FTR(ftr) => {
                if in_unit {
                    let mut test = BytesStart::new("Test");
                    test.push_attribute(("TestNum", ftr.test_num.to_string().as_str()));

                    // Use TestInfo consolidation: lookup cached test name from TSR
                    let test_name = if let Some(test_meta) = test_info_cache.get(&(ftr.test_num, ftr.head_num)) {
                        test_meta.test_name.as_str()
                    } else {
                        ftr.test_txt.as_str()
                    };
                    test.push_attribute(("TestName", test_name));
                    // OPTIMIZATION: Use pre-allocated string constant
                    test.push_attribute(("PF", if ftr.test_flg[0] & 0x80 != 0 { FAIL_STR } else { PASS_STR }));

                    xml_writer.write_event(Event::Empty(test))?;
                }
            }
            StdfRecord::MPR(mpr) => {
                if in_unit {
                    let mut test = BytesStart::new("Test");
                    test.push_attribute(("TestNum", mpr.test_num.to_string().as_str()));

                    // Use TestInfo consolidation: lookup cached test name from TSR
                    let test_name = if let Some(test_meta) = test_info_cache.get(&(mpr.test_num, mpr.head_num)) {
                        test_meta.test_name.as_str()
                    } else {
                        mpr.test_txt.as_str()
                    };
                    test.push_attribute(("TestName", test_name));
                    // OPTIMIZATION: Use pre-allocated string constant
                    test.push_attribute(("PF", if mpr.test_flg[0] & 0x80 != 0 { FAIL_STR } else { PASS_STR }));

                    xml_writer.write_event(Event::Empty(test))?;
                }
            }
            StdfRecord::PRR(prr) => {
                if in_unit {
                    let mut result = BytesStart::new("Result");
                    result.push_attribute(("X", prr.x_coord.to_string().as_str()));
                    result.push_attribute(("Y", prr.y_coord.to_string().as_str()));
                    result.push_attribute(("HardBin", prr.hard_bin.to_string().as_str()));
                    result.push_attribute(("SoftBin", prr.soft_bin.to_string().as_str()));
                    result.push_attribute(("TestTime", prr.test_t.to_string().as_str()));

                    xml_writer.write_event(Event::Empty(result))?;

                    xml_writer.write_event(Event::End(BytesEnd::new("Unit")))?;
                    in_unit = false;
                }
            }
            StdfRecord::MRR(_mrr) => {
                // Final cleanup
                close_all_open_tags(&mut xml_writer, &mut in_unit, &mut in_units, &mut in_wafer, &mut in_wafers, &mut in_lot)?;
            }
            // TSR records are already cached in the first pass for TestInfo consolidation
            // They don't generate their own XML elements, just provide metadata
            StdfRecord::TSR(_) => {
                // Skip - already cached in test_info_cache during analysis phase
            }
            _ => {}
        }
    }

    // Close any remaining open tags
    close_all_open_tags(&mut xml_writer, &mut in_unit, &mut in_units, &mut in_wafer, &mut in_wafers, &mut in_lot)?;

    // Close File and Xml elements
    xml_writer.write_event(Event::End(BytesEnd::new("File")))?;
    xml_writer.write_event(Event::End(BytesEnd::new("Xml")))?;

    Ok(output_meta)
}

pub fn extract_output_meta(path: &Path) -> anyhow::Result<OutputMeta> {
    let mut stdf_reader = StdfReader::new(path).map_err(|e| anyhow::anyhow!("{}", e))?;
    let mut output_meta = OutputMeta::empty();

    for record in stdf_reader.get_record_iter() {
        match record {
            Ok(StdfRecord::MIR(mir)) => {
                output_meta.tester = mir.tstr_typ.clone();
                output_meta.platform = mir.node_nam.clone();
                output_meta.session = mir.setup_t.to_string();
                break;
            }
            Ok(_) => {}
            Err(e) => return Err(anyhow::anyhow!("{}", e)),
        }
    }

    Ok(output_meta)
}

/// Helper to close all open tags in proper order
fn close_all_open_tags<W: Write>(
    xml_writer: &mut quick_xml::Writer<W>,
    in_unit: &mut bool,
    in_units: &mut bool,
    in_wafer: &mut bool,
    in_wafers: &mut bool,
    in_lot: &mut bool,
) -> anyhow::Result<()> {
    if *in_unit {
        xml_writer.write_event(Event::End(BytesEnd::new("Unit")))?;
        *in_unit = false;
    }
    if *in_units {
        xml_writer.write_event(Event::End(BytesEnd::new("Units")))?;
        *in_units = false;
    }
    if *in_wafer {
        xml_writer.write_event(Event::End(BytesEnd::new("Wafer")))?;
        *in_wafer = false;
    }
    if *in_wafers {
        xml_writer.write_event(Event::End(BytesEnd::new("Wafers")))?;
        *in_wafers = false;
    }
    if *in_lot {
        xml_writer.write_event(Event::End(BytesEnd::new("Lot")))?;
        *in_lot = false;
    }
    Ok(())
}

/// Emit Sites section (if GDR records exist)
fn emit_sites<W: Write>(
    xml_writer: &mut quick_xml::Writer<W>,
    records: &[StdfRecord],
) -> anyhow::Result<()> {
    let mut has_sites = false;

    for record in records {
        if let StdfRecord::GDR(_gdr) = record {
            if !has_sites {
                xml_writer.write_event(Event::Start(BytesStart::new("Sites")))?;
                has_sites = true;
            }
            // TODO: Parse GDR data to extract site information
            // For now, just emit a placeholder
            let mut site = BytesStart::new("Site");
            site.push_attribute(("Site", "0"));
            site.push_attribute(("Head", "1"));
            site.push_attribute(("SiteCount", "1"));

            xml_writer.write_event(Event::Empty(site))?;
        }
    }

    if has_sites {
        xml_writer.write_event(Event::End(BytesEnd::new("Sites")))?;
    }

    Ok(())
}

/// Emit Pins section (if GDR records exist)
fn emit_pins<W: Write>(
    xml_writer: &mut quick_xml::Writer<W>,
    records: &[StdfRecord],
) -> anyhow::Result<()> {
    let mut has_pins = false;

    for record in records {
        if let StdfRecord::GDR(_gdr) = record {
            if !has_pins {
                xml_writer.write_event(Event::Start(BytesStart::new("Pins")))?;
                has_pins = true;
            }
            // TODO: Parse GDR data to extract pin information
            // For now, just emit a placeholder
            let mut pin = BytesStart::new("Pin");
            pin.push_attribute(("Site", "0"));
            pin.push_attribute(("PinName", "unknown"));
            pin.push_attribute(("LogicalPinName", "unknown"));

            xml_writer.write_event(Event::Empty(pin))?;
        }
    }

    if has_pins {
        xml_writer.write_event(Event::End(BytesEnd::new("Pins")))?;
    }

    Ok(())
}

/// Format Unix timestamp to ISO 8601 string
fn format_timestamp(timestamp: u32) -> String {
    // TODO: Use chrono for proper timestamp formatting
    // For now, return as string representation
    timestamp.to_string()
}

