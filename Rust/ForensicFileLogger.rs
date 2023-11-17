use std::fs::{self, DirEntry};
use std::path::Path;
use std::time::UNIX_EPOCH;

fn main() {
    let path = "./"; // Directory to scan, change as needed
    match visit_dirs(Path::new(path), &log_file_details) {
        Ok(_) => println!("Scan complete."),
        Err(e) => eprintln!("Error during scan: {}", e),
    }
}

fn visit_dirs(dir: &Path, cb: &dyn Fn(&DirEntry)) -> std::io::Result<()> {
    if dir.is_dir() {
        for entry in fs::read_dir(dir)? {
            let entry = entry?;
            let path = entry.path();
            if path.is_dir() {
                visit_dirs(&path, cb)?;
            } else {
                cb(&entry);
            }
        }
    }
    Ok(())
}

fn log_file_details(entry: &DirEntry) {
    let path = entry.path();
    let metadata = match fs::metadata(&path) {
        Ok(metadata) => metadata,
        Err(e) => {
            eprintln!("Failed to get metadata for {:?}: {}", path, e);
            return;
        },
    };

    let file_size = metadata.len();
    let creation_time = metadata.created().map_or_else(
        |_| String::from("Unavailable"),
        |time| format!("{:?}", time.duration_since(UNIX_EPOCH).unwrap().as_secs()),
    );
    let modification_time = metadata.modified().map_or_else(
        |_| String::from("Unavailable"),
        |time| format!("{:?}", time.duration_since(UNIX_EPOCH).unwrap().as_secs()),
    );

    println!(
        "File: {:?}, Size: {} bytes, Created: {}, Modified: {}",
        path, file_size, creation_time, modification_time
    );
}
