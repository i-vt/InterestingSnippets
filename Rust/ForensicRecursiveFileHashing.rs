use std::{fs::{self, DirEntry}, path::Path, io::{self, Write}};
use sha2::{Sha256, Digest};
use std::time::UNIX_EPOCH;

fn main() -> io::Result<()> {
    let path = "./"; // Directory to scan
    let output_file = "forensic_log.txt"; // Output file

    let mut file = fs::File::create(output_file)?;
    writeln!(file, "File Forensics Report")?;
    writeln!(file, "====================\n")?;

    visit_dirs(Path::new(path), &mut file)?;

    println!("Forensic scan complete. Report saved to {}", output_file);
    Ok(())
}

fn visit_dirs(dir: &Path, file: &mut fs::File) -> io::Result<()> {
    if dir.is_dir() {
        for entry in fs::read_dir(dir)? {
            let entry = entry?;
            let path = entry.path();
            if path.is_dir() {
                visit_dirs(&path, file)?;
            } else {
                log_file_details(&entry, file)?;
            }
        }
    }
    Ok(())
}

fn log_file_details(entry: &DirEntry, file: &mut fs::File) -> io::Result<()> {
    let path = entry.path();
    let metadata = fs::metadata(&path)?;

    let file_size = metadata.len();
    let modification_time = metadata.modified().map_or_else(
        |_| String::from("Unavailable"),
        |time| format!("{:?}", time.duration_since(UNIX_EPOCH).unwrap().as_secs()),
    );

    let sha256_hash = calculate_sha256(&path)?;

    writeln!(
        file,
        "File: {:?}, Size: {} bytes, SHA-256: {}, Modified: {}",
        path.file_name().unwrap_or_default(),
        file_size, 
        sha256_hash, 
        modification_time
    )?;
    Ok(())
}

fn calculate_sha256(path: &Path) -> io::Result<String> {
    let mut file = fs::File::open(path)?;
    let mut hasher = Sha256::new();
    let mut buffer = [0; 1024];

    loop {
        let count = file.read(&mut buffer)?;
        if count == 0 {
            break;
        }
        hasher.update(&buffer[..count]);
    }

    Ok(format!("{:x}", hasher.finalize()))
}
