param ($ColdBoot = $False)

function New-Config {
    $Config = @{
        pubkey = Read-Host "Enter the pubkey to monitor"
        Recipient = Read-Host "Enter the Recipient Email Address"
        MailSender = Read-Host "Enter the Sender Email Address"
        MailServer = Read-Host "Enter the Mail Server Hostname"
        Port = Read-Host "Enter the Mail Server Port"
        Credential = Get-Credential -Message "Enter Username and Password for Mail Service"
        MiningWallet = Get-Credential -Message "Enter Wallet Name and Password for Mining Wallet" -UserName 'MiningWallet'
        StraxWallet = Get-Credential -Message "Enter Wallet Name and Password for Strax Wallet"
        StraxAddress = Read-Host "Enter your Strax address for crosschain transfers"
        ScriptPath = Read-Host "Enter the full path to where the Strax launch and Monitor-Node scripts are stored"
    }
    $Config | Export-Clixml .\Config.xml -Force
}


function Send-Mail {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]
        $Subject,
        [Parameter(Mandatory=$true)]
        [string]
        $Message
    )

    $MailMessage = @{
        To = $Config.Recipient
        From = $Config.MailSender
        Subject = $Subject
        Body = $Message
        SmtpServer = $Config.MailServer
        Port = $Config.Port
        Credential = $Config.Credential
    }

    try {
        Send-MailMessage @MailMessage -UseSsl
    } Catch {
        Write-Output $Error
    }
}


function Get-ServerResponse {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]
        $Network
    )

    if ($Network.ToLower() -eq 'strax') {
        $ApiPort = '17103'
    } elseif ($Network.ToLower() -eq 'cirrus') {
        $ApiPort = '37223'
    } else {
        throw "Invalid network"
    }

    $Uri = "http://localhost:{0}/api/node/status" -f $ApiPort

    try {
        $Res = Invoke-RestMethod -Method Get -Uri $Uri -ErrorAction SilentlyContinue
        return $Res
    } catch {
        return @{}
    }
}


function Get-FederationGatewayStatus {
    $Uri = 'http://localhost:17103/api/FederationGateway/info'

    try {
        $Res = Invoke-RestMethod -Method Get -Uri $Uri
        return $Res
    } catch {
        Write-Output "Checking Federation Gateway Status Failed."
    }
}


function Get-FedMemberInactivity {
    $Uri = 'http://localhost:37223/api/DefaultVoting/fedmembers'
    $FedMembers = Invoke-RestMethod -uri $Uri -Method Get

    return $FedMembers | Where-Object {$_.periodOfInactivity -notlike '00:*'}
}


function Get-CirrusBalance {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]
        $WalletName = 'MiningWallet'
    )

    $Uri = "http://localhost:37223/api/Wallet/balance?WalletName=$WalletName"
    try {
        $Res = Invoke-RestMethod -Method Get -Uri $Uri
        return $Res.balances[0].amountConfirmed / 1e8

    } catch {
        return "Error checking balance"
    }
}


function Find-Uptime {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [PSCustomObject]
        $Res
    )
    
    return $Res.runningTime
}

function Get-SpendableCoins {
    <#
    .SYNOPSIS
        Returns a lis of Spendable Transactions for a wallet and account

    .DESCRIPTION
        Get-SpendableCoins utilizes the REST Api endpoint /api/Wallet/spendable-transactions to return
        all Unspent Transaction Outputs (UTXOs) for a given wallet and account. 

    .PARAMETER WalletName
    Specifies the wallet name.

    .PARAMETER AccountName
    Specifies the Account Name to query. 'account 0' is the default.

    .PARAMETER BaseUri
    Specifies the Host presenting the REST Api for the wallet endpoints. 'http://localhost:17103' is 
    the default.

    .INPUTS
    
    None. You cannot pipe objects to Get-SpendableCoins.

    .OUTPUTS

    System.Array. Get-SpendableCoins returns a list of transaction objects.
    
    .EXAMPLE

    PS> Get-SpendableCoins -WalletName 'MyWallet' -AccountName 'account 1'

    id       index  address       isChange     amount  creationTime  confirmations
    --       -----  -------       --------     ------  ------------  -------------
    200d4...     2  XMBbvUp...    False     100717731    1605123328          37235
    200d4...     3  XMBbvUp...    False     100717731    1605123328          37235
    #>

    param (
        [Parameter(Mandatory=$true)][string]$WalletName,
        [string]$AccountName = 'account 0',
        [string]$BaseUri = 'http://localhost:37223'
    )

    $Uri = "{0}/api/Wallet/spendable-transactions?WalletName={1}&AccountName={2}" -f $BaseUri, $WalletName, [uri]::EscapeDataString($AccountName)
    $Coins = Invoke-RestMethod -Method Get -Uri $Uri
    return $Coins.transactions
}

function Send-SelectedCoinsCrsToStrax {
    <#
    .SYNOPSIS
        Returns a lis of Spendable Transactions for a wallet and account

    .DESCRIPTION
        Send-SelectedCoins utilizes the REST Api endpoint /api/Wallet/build-transaction and /api/wallet/send-transaction to send
        all or a specified amount from a selected set of coins to a specifyable destination address.

    .PARAMETER Coins
    Accepts an array of transaction objects

    .PARAMETER DestinationAddress
    Specifies the address of the destination wallet.
    
    .PARAMETER WalletName
    Specifies the wallet name.

    .PARAMETER Password
    Specifies the password for the selected wallet holding the coins.

    .PARAMETER AccountName
    Specifies the Account Name to query. 'account 0' is the default.

    .PARAMETER BaseUri
    Specifies the Host presenting the REST Api for the wallet endpoints. 'http://localhost:17103' is 
    the default.

    .PARAMETER Fee
    Specefies the amount of fee used for sending the transaction. '0.0002' is the default.

    .PARAMETER AmountForDestination
    Specifies the amount for the destination address to receive. Default is total amount of all selected coins.

    .INPUTS
    
    None. You cannot pipe objects to Get-SpendableCoins.

    .OUTPUTS

    System.Management.Automation.PSCustomObject. Send-SelectedCoins returns an object containing a transactionId and outputs objects
    consisting of combincations of address and amount.
    
    .EXAMPLE

    PS> Send-SelectedCoins -Coins $(Select-CoinsToSend) -DestinationAddress $DestinationAddress -WalletName 'MyWallet' -Password 'QwErTy123'

    transactionId  outputs                                                            
    -------------  -------                                                            
    bd274cb390...  {@{address=XC...; amount=13604196}}

    .LINK
    Select-CoinsToSend

    .LINK
    Get-SpendableCoins
    #>
    
    param (
        [Parameter(Mandatory=$true)] [array]$Coins,
        [Parameter(Mandatory=$true)] [string]$DestinationAddress,
        [Parameter(Mandatory=$true)] [string]$WalletName,
        [Parameter(Mandatory=$true)] [string]$Password,
        [string]$AccountName = 'account 0',
        [string]$BaseUri = 'http://localhost:37223',
        [double]$Fee = 0.0002,
        [double]$AmountForDestination,
        [string]$ChangeAddress        
    )

    $CoinsAmount = ($Coins.amount | Measure-Object -sum).sum / 1e8
    if (-not $ChangeAddress -and -not $AmountForDestination) {
        $AmountForDestination = $CoinsAmount - $Fee
        $ChangeAddress = $Coins[0].address
    } elseif ($ChangeAddress -and $AmountForDestination) {
        if ($AmountForDestination + $Fee -gt $CoinsAmount) {
            Write-Host "You made a bad calculation. You selected too few coins or entered a too high amount"
            exit
        }
    } else {
        Write-Host "You set on of the variables but not the other: AmountForDestination, ChangeAddress"
        exit
    }

    [array]$CoinOutpoints = foreach ($Coin in $Coins) {
        [pscustomobject]@{
            transactionId = $Coin.id
            index = $Coin.index
        }
    }

    [array]$Recipients = [pscustomobject] @{
        destinationAddress = "cYTNBJDbgjRgcKARAvi2UCSsDdyHkjUqJ2" # Cross chain contract for CRS --> STRAX
        amount = $AmountForDestination.ToString()
    }

    $BuildBody = ConvertTo-Json @{
        feeAmount = $Fee.ToString()
        password = $Password
        walletName = $WalletName
        accountName = $AccountName
        outpoints = $CoinOutpoints
        recipients = $Recipients
        changeAddress = $ChangeAddress
        opReturnData = $DestinationAddress
    }
    
    $BuildUri = "{0}/api/Wallet/build-transaction" -f $BaseUri
    $Tx = Invoke-RestMethod -Method Post -Uri $BuildUri -Body $BuildBody -ContentType "application/json"

    $SendBody = ConvertTo-Json @{
        hex = "$($Tx.hex)"
    }

    $SendUri =  "{0}/api/Wallet/send-transaction" -f $BaseUri
    return Invoke-RestMethod -Method Post -Uri $SendUri -Body $SendBody -ContentType "application/json"
}

function Start-Staking {
    param (
        [Parameter(Mandatory=$True)]$WalletName,
        [Parameter(Mandatory=$True)]$Password,
        $BaseUri = 'http://localhost:17103'
    )

    $Uri = "{0}/api/Staking/startStaking" -f $BaseUri
    $Body = ConvertTo-Json @{
        password=$Password
        name=$WalletName
    }
    Invoke-RestMethod -Method Post -Uri $Uri -Body $Body -ContentType "application/json"
    Start-Sleep 5
    $Staking = Invoke-RestMethod -Method Get -Uri "$BaseUri/api/Staking/getstakinginfo"
    if ($Staking.errors){
        return $Staking.errors
    } else { return $Staking | select enabled, staking}
}


if (! (Test-Path .\config.xml -ErrorAction SilentlyContinue)) {
    New-Config
} 

$Config = Import-Clixml .\config.xml

if ($ColdBoot) {
    Start-Sleep -Seconds 60
    Set-Location -Path $Config.ScriptPath
    & '.\STRAX Masternode Launch Script.ps1' -miningPassword $Config.MiningWallet.GetNetworkCredential().password
    Send-Mail -Subject "ColdBoot detected" -Message "The system just booted and ran the Masternode Launch Script at $(get-date -Format 'hh:mm:ss')"
    Start-Sleep -Seconds 300
    Start-Staking -WalletName $Config.StraxWallet.UserName -Password $Config.StraxWallet.GetNetworkCredential().Password
}

$HoursBetweenUpdates = 6
$MinuteUpdateInterval = 5
$MinutesElapsed = 0

while ($True) {
    $IsStraxUpNow = $true
    $IsCirrusUpNow = $true
    $MinutesElapsed += $MinuteUpdateInterval
    
    Write-Output "Last Update: $(Get-Date)"
    
    # Check for Strax Node availability. Send email if Strax is down.
    $StraxRes = Get-ServerResponse -Network Strax
    if ($IsStraxUpNow -and $StraxRes.count -eq 0) {
        Send-Mail -Subject "Strax Network down." -Message "Strax network detected down at $(get-date -Format 'hh:mm:ss')"
        $IsStraxUpNow = $false
    }
    
    # Check for Cirrus Node availability. Send email if Cirrus is down.
    if ($IsStraxUpNow) {
        $CirrusRes = Get-ServerResponse -Network Cirrus
        if ($IsCirrusUpNow -and $CirrusRes.count -eq 0) {
            Send-Mail -Subject "Strax Network down." -Message "Cirrus network detected down at $(get-date -Format 'hh:mm:ss')"
            $IsCirrusUpNow = $false
        }
    }

    # Check for Node Inactivity. Send email when not mined for more than an hour.
    if ($IsStraxUpNow -and $IsCirrusUpNow) {
        $FedMemberStatus = Get-FedMemberInactivity
        if ($Config.pubkey -in $FedMemberStatus.pubkey) {
            $MyActivity = $FedMemberStatus | Where-Object {$_.pubkey -eq $Config.pubkey}
            Send-Mail -Subject "Node not Mining." -Message "Node has been inactive since $($MyActivity.lastActiveTime). That is $($MyActivity.periodOfInactivity)"
        }
    }

    # Send status update email including uptime and Cirrus Balance every x hours. Also transfer Cirrus rewards to a Strax address cross chain, and report via email the amount sent.
    if ($MinutesElapsed -eq (60 * $HoursBetweenUpdates)) {
        Write-Output "Sending uptime e-mail."
        $Uptime = Find-Uptime -Res $StraxRes
        Send-Mail -Subject "Strax network uptime update" -Message "Strax uptime: $Uptime`nCirrus Balance: $(Get-CirrusBalance -WalletName $Config.MiningWallet.UserName)"
        
        $TX = Send-SelectedCoinsCrsToStrax -Coins $(Get-SpendableCoins -WalletName $Config.MiningWallet.UserName) -DestinationAddress $Config.StraxAddress `
            -WalletName $Config.MiningWallet.UserName -Password $Config.MiningWallet.GetNetworkCredential().password #-Fee 0.01
        Send-Mail -Subject 'Cross chain transaction' -Message "Sent $(($TX.outputs.amount | Where-Object {$_ -gt 0} | select -First 1) / 1e8) Strax to: $($Config.StraxAddress)"
        
        $MinutesElapsed = 0
    }

    Start-Sleep -Seconds ($MinuteUpdateInterval * 60)
}
