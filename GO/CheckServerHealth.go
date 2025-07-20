package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net"
	"os/exec"
	"runtime"
	"strconv"
	"time"

	"github.com/shirou/gopsutil/v3/cpu"
	"github.com/shirou/gopsutil/v3/disk"
	"github.com/shirou/gopsutil/v3/host"
	"github.com/shirou/gopsutil/v3/load"
	"github.com/shirou/gopsutil/v3/mem"
)

func getCPULoadStatus() map[string]interface{} {
	cores, _ := cpu.Counts(true)
	loads, err := load.Avg()

	if err == nil && runtime.GOOS != "windows" {
		overloaded := loads.Load1 > float64(cores)
		status := "Healthy"
		if overloaded {
			status = "Overloaded"
		}
		return map[string]interface{}{
			"type":        "load_average",
			"load_1_5_15": []float64{
				round(loads.Load1, 2),
				round(loads.Load5, 2),
				round(loads.Load15, 2),
			},
			"cpu_cores": cores,
			"status":    status,
		}
	}

	percentages, err := cpu.Percent(0, false)
	if err != nil || len(percentages) == 0 {
		return map[string]interface{}{"error": "CPU stats unavailable"}
	}
	status := "Healthy"
	if percentages[0] > 90 {
		status = "Overloaded"
	}
	return map[string]interface{}{
		"type":        "percent_usage",
		"cpu_percent": round(percentages[0], 2),
		"cpu_cores":   cores,
		"status":      status,
	}
}

func getAllDisksUsage() map[string]interface{} {
	partitions, err := disk.Partitions(true)
	if err != nil {
		return map[string]interface{}{"error": "Unable to list partitions: " + err.Error()}
	}

	var total, used, free float64
	var usagePercents []float64
	var details []map[string]interface{}
	seen := map[string]bool{}

	for _, p := range partitions {
		if seen[p.Mountpoint] {
			continue
		}
		seen[p.Mountpoint] = true

		u, err := disk.Usage(p.Mountpoint)
		if err != nil || u.Total == 0 {
			continue
		}

		total += float64(u.Total)
		used += float64(u.Used)
		free += float64(u.Free)
		usagePercents = append(usagePercents, u.UsedPercent)

		details = append(details, map[string]interface{}{
			"mount":         u.Path,
			"fs_type":       u.Fstype,
			"total_GB":      round(float64(u.Total)/1e9, 2),
			"used_GB":       round(float64(u.Used)/1e9, 2),
			"free_GB":       round(float64(u.Free)/1e9, 2),
			"usage_percent": round(u.UsedPercent, 2),
		})
	}

	avgUsage := 0.0
	if len(usagePercents) > 0 {
		for _, p := range usagePercents {
			avgUsage += p
		}
		avgUsage /= float64(len(usagePercents))
	}

	summary := map[string]interface{}{
		"total_GB":              round(total/1e9, 2),
		"used_GB":               round(used/1e9, 2),
		"free_GB":               round(free/1e9, 2),
		"average_usage_percent": round(avgUsage, 2),
	}

	return map[string]interface{}{
		"partitions":            details,
		"all_partitions_summary": summary,
	}
}


func getMemoryUsage() map[string]interface{} {
	v, err := mem.VirtualMemory()
	if err != nil {
		return map[string]interface{}{"error": err.Error()}
	}
	return map[string]interface{}{
		"total_MB":      round(float64(v.Total)/1024/1024, 2),
		"used_MB":       round(float64(v.Used)/1024/1024, 2),
		"free_MB":       round(float64(v.Available)/1024/1024, 2),
		"usage_percent": round(v.UsedPercent, 2),
	}
}

func getUptime() string {
	uptime, err := host.Uptime()
	if err != nil {
		return "Unavailable"
	}
	return time.Duration(uptime * uint64(time.Second)).String()
}

func checkNetwork(host string) map[string]string {
	status := "Unknown"

	var cmd *exec.Cmd
	if runtime.GOOS == "windows" {
		cmd = exec.Command("ping", "-n", "1", host)
	} else {
		cmd = exec.Command("ping", "-c", "1", "-W", "1", host)
	}
	var out bytes.Buffer
	cmd.Stdout = &out
	err := cmd.Run()
	if err == nil {
		status = "Online"
	} else {
		conn, err := net.DialTimeout("tcp", net.JoinHostPort(host, "80"), time.Second)
		if err == nil {
			conn.Close()
			status = "Online"
		} else {
			status = "Offline"
		}
	}
	return map[string]string{
		"target": host,
		"status": status,
	}
}

func getOSInfo() map[string]string {
	info, _ := host.Info()
	return map[string]string{
		"system":   info.OS,
		"release":  info.PlatformVersion,
		"version":  info.KernelVersion,
		"hostname": info.Hostname,
		"uptime":   getUptime(),
	}
}

func healthCheck() map[string]interface{} {
	return map[string]interface{}{
		"timestamp":     time.Now().Format(time.RFC3339),
		"os_info":       getOSInfo(),
		"cpu":           getCPULoadStatus(),
		"memory":        getMemoryUsage(),
		"disk":          getAllDisksUsage(),
		"network_check": checkNetwork("8.8.8.8"),
	}
}

func round(val float64, precision int) float64 {
	format := fmt.Sprintf("%%.%df", precision)
	valStr := fmt.Sprintf(format, val)
	result, _ := strconv.ParseFloat(valStr, 64)
	return result
}

func main() {
	result := healthCheck()
	jsonBytes, err := json.MarshalIndent(result, "", "  ")
	if err != nil {
		fmt.Println(`{"error": "Failed to serialize JSON"}`)
		return
	}
	fmt.Println(string(jsonBytes))
}
