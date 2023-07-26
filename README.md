# Purpose

This repository contains a Bicep template to setup:
- 2 App Service Linux (instance 0 and 1)
- Azure Front Door in front of both,
- By default traffic will hit instance 0,
- If `X-Color` header is specified with value `green`, it will hit instance 1 thanks to a route rule.

There is also a very basic API backend.

# Deploy the infrastructure

```powershell
$subscription = "Training Subscription"

az login
az account set --subscription $subscription

$rgName = "frbar-fd-fo"
$envName = "fbz12"
$location = "West Europe"

az group create --name $rgName --location $location
az deployment group create --resource-group $rgName --template-file infra.bicep --mode complete --parameters envName=$envName
```

# Build and Deploy the API backend

```powershell
dotnet publish .\api\ -r linux-x64 --self-contained -o publish
Compress-Archive publish\* publish.zip -Force
az webapp deployment source config-zip --src .\publish.zip -n "$($envName)-api-0" -g $rgName
az webapp deployment source config-zip --src .\publish.zip -n "$($envName)-api-1" -g $rgName

Remove-Item publish -Recurse
Remove-Item publish.zip
```

# Get the Azure Front Door endpoint

And note it for later reference.

```powershell
az afd endpoint list -g $rgName --profile-name "$($envName)-afd" --query [0].hostName
```

# Test

Play with the `X-Color` header below:

```powershell
$endpoint = az afd endpoint list -g $rgName --profile-name "$($envName)-afd" --query [0].hostName -otsv
$url = "https://$endpoint/api/hello-world"  

write-output "Let's ping $url"

while ($true) {  
    $response = Invoke-WebRequest -Uri $url -UseBasicParsing -Headers @{ "X-Color" = "green" }
    $firstLine = $response.Content.Split("`n")[0]  
  
    Write-Output "$(get-date -format "HH:mm:ss") $firstLine"
  
    Start-Sleep -Seconds 1  
}  
```

# Tear down

```powershell
az group delete --name $rgName
```

