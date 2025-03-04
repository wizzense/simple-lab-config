# simple-lab-config

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/wizzense/simple-lab-config/refs/heads/main/config.json' -OutFile '.\config.json'; Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/wizzense/simple-lab-config/refs/heads/main/kicker.ps1' -OutFile '.\kicker.ps1'; .\kicker.ps1"
