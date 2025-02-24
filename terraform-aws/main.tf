provider "aws" {
  region = "us-east-1"
}

# Criar chave SSH para descriptografar a senha
resource "tls_private_key" "rsa_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "aws_key_pair" "generated_key" {
  key_name   = "chave-terraform"
  public_key = tls_private_key.rsa_key.public_key_openssh
}

resource "local_file" "private_key" {
  filename        = "${path.module}/chave-terraform.pem"
  content         = tls_private_key.rsa_key.private_key_pem
  file_permission = "0600"
}

# Criar Security Group para RDP e WinRM
resource "aws_security_group" "winrm_sg" {
  name        = "winrm_sg"
  description = "Habilita RDP e WinRM HTTPS"

  ingress {
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] 
  }

  ingress {
    from_port   = 5986
    to_port     = 5986
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Criar Instância Windows Server
resource "aws_instance" "windows_vm" {
  ami             = "ami-0893df1bd754c3189" # AMI do Windows Server 2019
  instance_type   = "t2.micro"
  key_name        = aws_key_pair.generated_key.key_name
  security_groups = [aws_security_group.winrm_sg.name]

  tags = {
    Name = "Windows-Server"
  }

# Script PowerShell para configurar WinRM e definir senha automaticamente
  user_data = <<EOF
<powershell>

Start-Transcript -Path C:\setup-log.txt -Append

# Definir a senha do Administrador
$Password = ConvertTo-SecureString "Renegade123" -AsPlainText -Force
Set-LocalUser -Name "Administrator" -Password $Password
wmic UserAccount where Name='Administrator' set PasswordExpires=False
Enable-LocalUser -Name "Administrator"

# Configurar WinRM para rodar automaticamente
Set-Service -Name winrm -StartupType Automatic
Start-Service winrm
Start-Sleep -Seconds 5  # Espera para garantir que o serviço está rodando

# Criar certificado autoassinado para WinRM
$cert = New-SelfSignedCertificate -DnsName "$env:COMPUTERNAME" -CertStoreLocation "Cert:\\LocalMachine\\My"
Start-Sleep -Seconds 5

# Capturar o thumbprint do certificado recém-criado
$thumbprint = $cert.Thumbprint

# Remover qualquer listener WinRM existente na porta 5986
winrm delete winrm/config/Listener?Address=*+Transport=HTTPS

# Criar listener HTTPS corretamente
winrm create winrm/config/Listener?Address=*+Transport=HTTPS "@{Hostname=`"$env:COMPUTERNAME`"; CertificateThumbprint=`"$thumbprint`"}"

# Configurar WinRM para permitir autenticação básica e tráfego seguro
winrm set winrm/config/service/Auth '@{Basic="true"}'
winrm set winrm/config/service '@{AllowUnencrypted="false"}'

# Habilitar tráfego HTTPS no firewall
New-NetFirewallRule -Name "WinRM-HTTPS" -DisplayName "WinRM HTTPS 5986" -Protocol TCP -LocalPort 5986 -Action Allow -Direction Inbound

# Reiniciar o serviço WinRM
Restart-Service winrm
Start-Sleep -Seconds 5

Stop-Transcript
</powershell>
EOF
}

# Exibir o IP da instância
output "public_ip" {
  value = aws_instance.windows_vm.public_ip
}
