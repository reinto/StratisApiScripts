# This is a Cirrus Chain Fed Member Bot written in Powershell

param (
    $WebhookUri
)

$FedMemberUri = 'http://localhost:37223/api/DefaultVoting/fedmembers'
$FedMembers = Invoke-RestMethod -Uri $FedMemberUri -Method Get
$FedMembersOffline = $FedMembers | Where-Object {
    $_.periodOfInactivity -notlike '00:*' -and $_.periodOfInactivity -notlike '01:*' -and $_.pubkey -notlike '02ace4*'
}

[System.Collections.ArrayList]$EmbedArray = @()
$Color = '16711680'
$Title = 'Inactive Block Producers'
$CustomImageUrl = 'https://i.ytimg.com/vi/UoStgb4P6xU/hqdefault.jpg'

if ($FedMembersOffline) {
    $Description = "The following Block Producers have been inactive for over two hours."

    [array]$Fields = foreach ($Member in $FedMembersOffline) {
        [PSCustomObject]@{
            name = $Member.pubkey.substring(0,6)
            value = $Member.periodOfInactivity
            inline = $true
        }
    }
    
    $Image = [PSCustomObject]@{
        url = $CustomImageUrl
        height = 200
        width = 200
    }
    
    $EmbedObject = [PSCustomObject]@{
        color = $Color
        title = $Title
        description = $Description
        fields = $Fields
        image = $Image
    }
} else {
    $Description = "No inactive Block Producers."
    
    $EmbedObject = [PSCustomObject]@{
        color = $Color
        title = $Title
        description = $Description
    }
}

$EmbedArray.Add($EmbedObject)

$Payload = [PSCustomObject]@{
    embeds = $EmbedArray
}

Invoke-RestMethod -Uri $WebhookUri -Method Post -Body ($Payload | ConvertTo-Json -Depth 4) -ContentType 'application/json'
