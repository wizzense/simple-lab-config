Set-ExecutionPolicy -ExecutionPolicy Bypass

Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/wizzense/opentofu-lab-automation/refs/heads/dev/kicker-bootstrap.ps1' -OutFile '.\kicker-bootstrap.ps1'

& .\kicker-boostrap.ps1