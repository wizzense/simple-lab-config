Set-ExecutionPolicy -ExecutionPolicy Bypass

Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/wizzense/opentofu-lab-automation/refs/heads/main/kicker-git.ps1' -OutFile '.\kicker-git.ps1'

& .\kicker-git.ps1

