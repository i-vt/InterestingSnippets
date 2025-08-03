# Linux

## Install .NET
```
# Check if .NET is installed
dotnet --version

# If not installed, install it (Ubuntu/Debian example):
wget https://packages.microsoft.com/config/ubuntu/20.04/packages-microsoft-prod.deb -O packages-microsoft-prod.deb
sudo dpkg -i packages-microsoft-prod.deb
sudo apt-get update
sudo apt-get install -y dotnet-sdk-8.0
```

## Create Project
```
mkdir ProjectNameGoesH3re
cd ProjectNameGoesH3re
dotnet new console
```

## Cross-Compile
```
# For Windows x64 (most common)
dotnet publish -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true

# For Windows x86 (32-bit)
dotnet publish -c Release -r win-x86 --self-contained true -p:PublishSingleFile=true

# For Windows ARM64
dotnet publish -c Release -r win-arm64 --self-contained true -p:PublishSingleFile=true
```

## Output
```
ls -lah ./bin/Release/net8.0/win-x64/publish/ProjectNameGoesH3re.exe
```
The ProjectNameGoesH3re.pdb file can be safely ignored
