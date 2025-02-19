# simple-lab-config

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command `
"Invoke-WebRequest -Uri 'https://github.com/wizzense/simple-lab-config/config.json' -OutFile '.\config.json'; `
 Invoke-WebRequest -Uri 'https://github.com/wizzense/simple-lab-config/kicker.ps1' -OutFile '.\kicker.ps1'; `
 .\kicker.ps1"