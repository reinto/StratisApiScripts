# This is a Cirrus Chain Fed Member Bot written in Powershell

param (
    $WebhookUri
)

$FedMemberUri = 'http://localhost:37223/api/DefaultVoting/fedmembers'
$FedMembers = Invoke-RestMethod -Uri $FedMemberUri -Method Get
$FedMembersOffline = $FedMembers | Where-Object {$_.periodOfInactivity -notlike '00:*' -and $_.periodOfInactivity -notlike '01:*'}

[System.Collections.ArrayList]$EmbedArray = @()
$Color = '16711680'
$Title = 'Inactive Block Producers'


if ($FedMembersOffline) {
    $Description = "The following Block Producers have been inactive for over two hours."

    $Fields = foreach ($Member in $FedMembersOffline) {
        [PSCustomObject]@{
            name = $Member.pubkey.substring(0,6)
            value = $Member.periodOfInactivity
            inline = $true
        }
    }
} else {
    $Description = "No inactive Block Producers."
}

$EmbedObject = [PSCustomObject]@{
    color = $Color
    title = $Title
    description = $Description
    fields = $Fields
}

$EmbedArray.Add($EmbedObject)

$Payload = [PSCustomObject]@{
    embeds = $EmbedArray
}

Invoke-RestMethod -Uri $WebhookUri -Method Post -Body ($Payload | ConvertTo-Json -Depth 4) -ContentType 'application/json'
