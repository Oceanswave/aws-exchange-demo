Import-Module ExchangeOnlineManagement
# Import-Module MSOnline  #this may or may not be necessary.
Connect-ExchangeOnline -ShowProgress $false -AppId $env:AAD_APPID -CertificateFilePath "$env:CERT_PATH" -CertificatePassword (ConvertTo-SecureString -String $env:CERT_PASSWORD -AsPlainText -Force) -Organization $env:AAD_ORG
Get-MailContact -Identity "Ryan Howard" | Format-List
Disconnect-ExchangeOnline -Confirm:$false