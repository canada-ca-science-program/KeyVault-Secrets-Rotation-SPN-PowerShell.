using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

function GetAlternateCredentialId($credentialId){
    #Write code to get alternate credential id for your service

   #EXAMPLE FOR STORAGE

   <#
   $validCredentialIdsRegEx = 'key[1-2]'
   
   If($credentialId -NotMatch $validCredentialIdsRegEx){
       throw "Invalid credential id: $credentialId. Credential id must follow this pattern:$validCredentialIdsRegEx"
   }
   If($credentialId -eq 'key1'){
       return "key2"
   }
   Else{
       return "key1"
   }
   #>
}

function RegenerateCredential($providerAddress){
    
    
    
    Write-Host "Regenerating credential. Id: $credentialId Resource Id: $providerAddress"
    #get enterprise App 
    $spn = Get-AzADServicePrincipal -ObjectId $providerAddress
    
    #get reg app 
    
    $app = Get-AzADApplication -ApplicationId $spn.AppId

    #nuke all old keys 

    $app | Remove-AzADAppCredential

    #create new secret     
    $newSecret = $app | New-AzADAppCredential 

    #return key secret  
    return $newSecret.SecretText


    #Write code to regenerate credential, update your service with new credential and return it

    #EXAMPLE FOR STORAGE

    <#  
    $storageAccountName = ($providerAddress -split '/')[8]
    $resourceGroupName = ($providerAddress -split '/')[4]
    
    #Regenerate key 
    $operationResult = New-AzStorageAccountKey -ResourceGroupName $resourceGroupName -Name $storageAccountName -KeyName $credentialId
    $newCredentialValue = (Get-AzStorageAccountKey -ResourceGroupName $resourceGroupName -AccountName $storageAccountName|where KeyName -eq $credentialId).value 
    return $newCredentialValue
    
    #>
}

function RemediateAcvcount(){

    
}

function AddSecretToKeyVault($keyVAultName,$secretName,$secretvalue,$exprityDate,$tags){
    
     Set-AzKeyVaultSecret -VaultName $keyVAultName -Name $secretName -SecretValue $secretvalue -Tag $tags -Expires $expiryDate

}

function RoatateSecret($keyVaultName,$secretName){
    #Retrieve Secret
    $secret = (Get-AzKeyVaultSecret -VaultName $keyVAultName -Name $secretName)
    Write-Host "Secret Retrieved"
    
    #Retrieve Secret Info
    $validityPeriodDays = $secret.Tags["ValidityPeriodDays"]
    $credentialId=  $secret.Tags["CredentialId"]
    $providerAddress = $secret.Tags["ProviderAddress"]
    
    Write-Host "Secret Info Retrieved"
    Write-Host "Validity Period: $validityPeriodDays"
    Write-Host "Credential Id: $credentialId"
    Write-Host "Provider Address: $providerAddress"

    #Get Credential Id to rotate - alternate credential
    $alternateCredentialId = GetAlternateCredentialId $credentialId
    Write-Host "Alternate credential id: $alternateCredentialId"

    #Regenerate alternate access credential in provider
    $newCredentialValue = (RegenerateCredential $providerAddress)
    Write-Host "Credential regenerated. Credential Id: $alternateCredentialId Resource Id: $providerAddress"

    #Add new credential to Key Vault
    $newSecretVersionTags = @{}
    $newSecretVersionTags.ValidityPeriodDays = $validityPeriodDays
    $newSecretVersionTags.CredentialId=$alternateCredentialId
    $newSecretVersionTags.ProviderAddress = $providerAddress

    $expiryDate = (Get-Date).AddDays([int]$validityPeriodDays).ToUniversalTime()
    $secretvalue = ConvertTo-SecureString "$newCredentialValue" -AsPlainText -Force
    AddSecretToKeyVault $keyVAultName $secretName $secretvalue $expiryDate $newSecretVersionTags

    Write-Host "New credential added to Key Vault. Secret Name: $secretName"
}


# Write to the Azure Functions log stream.
Write-Host "HTTP trigger function processed a request."

Try{
    #Validate request paramaters
    $keyVAultName = $Request.Query.KeyVaultName
    $secretName = $Request.Query.SecretName
    if (-not $keyVAultName -or -not $secretName ) {
        $status = [HttpStatusCode]::BadRequest
        $body = "Please pass a KeyVaultName and SecretName on the query string"
        break
    }
    
    Write-Host "Key Vault Name: $keyVAultName"
    Write-Host "Secret Name: $secretName"
    
    #Rotate secret
    Write-Host "Rotation started. Secret Name: $secretName"
    RoatateSecret $keyVAultName $secretName

    $status = [HttpStatusCode]::Ok
    $body = "Secret Rotated Successfully"
     
}
Catch{
    $status = [HttpStatusCode]::InternalServerError
    $body = "Error during secret rotation"
    Write-Error "Secret Rotation Failed: $_.Exception.Message"
}
Finally
{
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = $status
        Body = $body
    })
}

