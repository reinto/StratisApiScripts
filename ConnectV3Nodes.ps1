### Declare and set script constants
[string]$CorrectVersionString = 'StratisNode:3.0.0 (70012)'
[Uri]$StratisApiBaseUri = 'http://localhost:37221/api/'
[Uri]$CryptoIdBaseUri = 'http://chainz.cryptoid.info/strat/api.dws'
[string]$GetPeerInfoRelativePath = "ConnectionManager/getpeerinfo"
[string]$AddNodeRelativePath = 'ConnectionManager/addnode?endpoint='
[string]$LastSeenNodesRelativePath = "?q=nodes"

### Add all nodes to a list containing IP and intended action. Then execute the action against the Stratis Full Node API.
function Reconnect-Nodes
{
    param
    (
        [Parameter(Mandatory=$false)]$Remove,
        [Parameter(Mandatory=$false)]$Add
    )

    $Nodelist = New-Object System.Collections.ArrayList
    if ($Remove)
    {
        foreach ($LegacyPeerIp in $Remove)
        {
            $null = $Nodelist.Add("$LegacyPeerIp,remove")
        }
    }
    
    if ($add)
    {
        foreach ($V3PeerIp in $Add)
        {
            $null = $Nodelist.Add("$V3PeerIp,add")
        }
    }

    $ActionTaken = foreach ($Node in $Nodelist)
    {
        $PeerIp, $Command = $Node -split '\,'
        $AddNodeUri = "{0}{1}{2}&command={3}" -f $StratisApiBaseUri, $AddNodeRelativePath, $PeerIp, $Command
        $Success = Invoke-RestMethod -Uri $AddNodeUri
        [PSCustomObject]@{
            'Peer IP Address' = $PeerIp
            'Action Taken' = $Command
            'Successful' = $Success
        }
    }
    
    if (!$Add -and !$Remove)
    {
        Write-Host "Exception: No nodes specified to add or remove." -ForegroundColor Red
    }
    
    return $ActionTaken
}

### Lists all Legacy nodes currently connected to, from the Stratis Full Node API
function Get-LegacyPeers
{
    $Peers = Invoke-RestMethod -Uri ("{0}{1}" -f $StratisApiBaseUri, $GetPeerInfoRelativePath)
    $LegacyPeers = $Peers | where {$_.subver -ne $CorrectVersionString}
    $PeerIps = foreach ($LegacyPeerIp in $LegacyPeers.addr)
    {
        (($LegacyPeerIp -split ']')[0] -split ':')[-1]
    }
    return $PeerIps
}

### Lists all recently seen V3 nodes, from the CryptoID.info API
function Get-LastSeenV3Nodes
{
    $LastSeenNodes = Invoke-RestMethod -Uri ("{0}{1}" -f $CryptoIdBaseUri, $LastSeenNodesRelativePath)
    $LastSeenV3Nodes = ($LastSeenNodes | where {$_.subver -eq $CorrectVersionString}).nodes
    return $LastSeenV3Nodes
}

### Run script
$LegacyNodes = Get-LegacyPeers
$V3Nodes = Get-LastSeenV3Nodes
Reconnect-Nodes -Remove $LegacyNodes -Add $V3Nodes
