//GOOS=windows GOARCH=amd64 go build -o myprogram.exe main.go
package main

import (
	"fmt"
	"os/exec"
)

func main() {
	// Execute whoami command through cmd.exe and redirect output to lol.txt
	cmd := exec.Command("cmd.exe", "/C", "whoami > ./lol.txt")
	
	// Run the command
	err := cmd.Run()
	if err != nil {
		fmt.Printf("Error executing command: %v\n", err)
		return
	}
	
	fmt.Println("Command executed successfully!")
}
