#![allow(dead_code)]
use serde::Serialize;


// --- Top Level ---

#[derive(Debug, Serialize)]
#[serde(rename = "File")]
pub struct FileRecord {
    #[serde(rename = "FileName")]
    pub file_name: String,
    #[serde(rename = "CPUType")]
    pub cpu_type: u8,
    #[serde(rename = "STDFVersion")]
    pub stdf_version: u8,
}

// --- Lot Level ---

#[derive(Debug, Serialize)]
#[serde(rename = "Lot")]
pub struct LotRecord {
    #[serde(rename = "LotId")]
    pub lot_id: String,
    #[serde(rename = "PartType")]
    pub part_type: String, // MIR: PART_TYP
    #[serde(rename = "NodeName")]
    pub node_name: String,
    #[serde(rename = "TesterType")]
    pub tester_type: String,
    #[serde(rename = "JobName")]
    pub job_name: String,
    #[serde(rename = "JobRevision")]
    pub job_rev: String,
    #[serde(rename = "SublotId")]
    pub sblot_id: String, // MIR: SBLOT_ID
    #[serde(rename = "OperatorName")]
    pub oper_nam: String,
    #[serde(rename = "ExecType")]
    pub exec_typ: String,
    #[serde(rename = "ExecVersion")]
    pub exec_ver: String,
    #[serde(rename = "TestCode")]
    pub test_cod: String,
    #[serde(rename = "TestTemperature")]
    pub tst_temp: String,
    #[serde(rename = "UserText")]
    pub user_txt: String,
    #[serde(rename = "AuxFile")]
    pub aux_file: String,
    #[serde(rename = "PackageType")]
    pub pkg_typ: String,
    #[serde(rename = "FamilyId")]
    pub famly_id: String,
    #[serde(rename = "DateCode")]
    pub date_cod: String,
    #[serde(rename = "FacilityId")]
    pub facil_id: String,
    #[serde(rename = "FloorId")]
    pub floor_id: String,
    #[serde(rename = "ProcessId")]
    pub proc_id: String,
    #[serde(rename = "OperationFrequency")]
    pub oper_frq: String,
    #[serde(rename = "SpecName")]
    pub spec_nam: String,
    #[serde(rename = "SpecVersion")]
    pub spec_ver: String,
    #[serde(rename = "FlowId")]
    pub flow_id: String,
    #[serde(rename = "SetupId")]
    pub setup_id: String,
    #[serde(rename = "DesignRevision")]
    pub dsgn_rev: String,
    #[serde(rename = "EngLotId")]
    pub eng_id: String,
    #[serde(rename = "RomCode")]
    pub rom_cod: String,
    #[serde(rename = "TesterSerial")]
    pub serl_num: String,
    #[serde(rename = "SupervisorName")]
    pub supr_nam: String,

    // Fields from first MRR (often merged into Lot in XML) for the closing but might be attributes
    #[serde(rename = "FinishTime")]
    pub finish_time: String, 
}

// --- Wafer Level ---

#[derive(Debug, Serialize)]
#[serde(rename = "Wafer")]
pub struct WaferRecord {
    #[serde(rename = "WaferId")]
    pub wafer_id: String,
    #[serde(rename = "StartTime")]
    pub start_time: String,
    // Note: CSV maps WRR fields to Wafer element too, like FinishTime, PartCount etc.
}

#[derive(Debug, Serialize)]
#[serde(rename = "WaferSummary")]
pub struct WaferSummary {
    #[serde(rename = "FinishTime")]
    pub finish_time: String,
    #[serde(rename = "PartCount")]
    pub part_cnt: u32,
    #[serde(rename = "RetestCount")]
    pub rtst_cnt: u32,
    #[serde(rename = "AbortCount")]
    pub abrt_cnt: u32,
    #[serde(rename = "GoodCount")]
    pub good_cnt: u32,
    #[serde(rename = "FunctionalCount")]
    pub func_cnt: u32,
}


// --- Unit Level ---

#[derive(Debug, Serialize)]
#[serde(rename = "Unit")]
pub struct UnitRecord {
    #[serde(rename = "Head")]
    pub head_num: u8,
    #[serde(rename = "Site")]
    pub site_num: u8,
    // Fields from PRR at end
    #[serde(rename = "InitialTestCount")]
    pub num_test: u16,
    #[serde(rename = "HardBin")]
    pub hard_bin: u16,
    #[serde(rename = "SoftBin")]
    pub soft_bin: u16,
    #[serde(rename = "X")]
    pub x_coord: i16, // Use i16 for coordinates
    #[serde(rename = "Y")]
    pub y_coord: i16,
    #[serde(rename = "TestTime")]
    pub test_t: u32,
    #[serde(rename = "PartId")]
    pub part_id: String,
    #[serde(rename = "PartText")]
    pub part_txt: String,
}

// --- Test/Meas Level ---

#[derive(Debug, Serialize)]
#[serde(rename = "Meas")]
pub struct MeasRecord {
    #[serde(rename = "TestNum")]
    pub test_num: u32,
    #[serde(rename = "Head")]
    pub head_num: u8,
    #[serde(rename = "Site")]
    pub site_num: u8,
    #[serde(rename = "Val")]
    pub result: Option<f32>, // PTR RESULT or MPR Value
    #[serde(rename = "PF")]
    pub pass_fail: String, // Calculated from TEST_FLG
    #[serde(rename = "TestText")]
    pub test_txt: String,
    #[serde(rename = "AlarmId")]
    pub alarm_id: Option<String>,
    
    // Limits and Units (Optional/Optimization: Only on first occurrence?)
    // The CSV says "Only FIRST Record !!!" for these, implying optimization.
    #[serde(rename = "Units")]
    pub units: Option<String>,
    #[serde(rename = "LowLimit")]
    pub lo_limit: Option<f32>,
    #[serde(rename = "HighLimit")]
    pub hi_limit: Option<f32>,
}

#[derive(Debug, Serialize)]
#[serde(rename = "Bin")]
pub struct BinRecord {
    #[serde(rename = "Type")]
    pub bin_type: String, // "Hardware" or "Software"
    #[serde(rename = "Number")]
    pub number: u16,
    #[serde(rename = "Count")]
    pub count: u32,
    #[serde(rename = "PassFail")]
    pub pf: String,
    #[serde(rename = "Name")]
    pub name: String,
}

#[derive(Debug, Serialize)]
#[serde(rename = "Audit")]
pub struct AuditRecord {
    #[serde(rename = "ModificationTime")]
    pub mod_time: String,
    #[serde(rename = "CMDLine")]
    pub cmd_line: String,
}

#[derive(Debug, Clone)]
pub struct OutputMeta {
    pub tester: String,
    pub platform: String,
    pub session: String,
}

impl OutputMeta {
    pub fn empty() -> Self {
        Self {
            tester: String::new(),
            platform: String::new(),
            session: String::new(),
        }
    }
}
