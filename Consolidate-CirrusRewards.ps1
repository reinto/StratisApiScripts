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

function Send-SelectedCoins {
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
        [string]$BaseUri = 'http://localhost:17103',
        [double]$Fee = 0.0002,
        [double]$AmountForDestination,
        [string]$ChangeAddress        
    )

    $CoinsAmount = ($Coins.amount | Measure-Object -sum).sum / 1e8
    if (-not $ChangeAddress -and -not $AmountForDestination) {
        $AmountForDestination = $CoinsAmount - $Fee
        $ChangeAddress = $DestinationAddress
    } elseif ($ChangeAddress -and $AmountForDestination) {
        if ($AmountForDestination + $Fee -gt $CoinsAmount) {
            Write-Host "You made a bad calculation. You selected too few coins or entered a too high amount"
            exit
        }
    } else {
        Write-Host "You set one of the variables but not the other: AmountForDestination, ChangeAddress"
        exit
    }
        
    [array]$CoinOutpoints = foreach ($Coin in $Coins) {
        [pscustomobject]@{
            transactionId = $Coin.id
            index = $Coin.index
        }
    }

    [array]$Recipients = [pscustomobject] @{
        destinationAddress = $DestinationAddress
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
    }
    
    $BuildUri = "{0}/api/Wallet/build-transaction" -f $BaseUri
    $Tx = Invoke-RestMethod -Method Post -Uri $BuildUri -Body $BuildBody -ContentType "application/json"

    $SendBody = ConvertTo-Json @{
        hex = "$($Tx.hex)"
    }

    $SendUri =  "{0}/api/Wallet/send-transaction" -f $BaseUri
    return Invoke-RestMethod -Method Post -Uri $SendUri -Body $SendBody -ContentType "application/json"
}

#################### Contstants ####################

<#
Set the number of coins (UTXOs) you want to include in a single consolidation. The larger the set, 
the more likely the smallest coins will remain in your wallet. Don't go over 1000 as it's not supported.
#>
$CoinsPerCoinSet = 950

<#
Better set an unused address as destination. After running this script you can transfer all resulting 
coins to STRAX.
#>
$DestinationAddress = Read-Host "Enter an unused destination address to consolidate to"

# Don't set the fee to low, or transactions will fail. 0.01 CRS will usually get the job done.
$Fee = 0.01

#################### Contstants ####################

$Creds = Get-Credential -UserName 'MiningWallet' -Message "Wallet Name as Username and Wallet Password"

$WalletName = $Creds.GetNetworkCredential().UserName
$Password = $Creds.GetNetworkCredential().Password
$BaseUri = 'http://localhost:37223'
$AccountName = 'account 0'

$UTXOsToConsolidate = Get-SpendableCoins -WalletName $WalletName -BaseUri $BaseUri -AccountName $AccountName | Where-Object {$_.confirmations -gt 10} | Sort-Object -Property amount -Descending

<#
By dividing the number of eligible coins by the the number of coins per consolidation round and 
storing it in an integer (whole number), you are rounding down the result of the equation.
#>
$TransactionsToSend = [int32]($UTXOsToConsolidate.Count / $CoinsPerCoinSet)

$TXs = foreach ($CoinSet in 0..($TransactionsToSend - 1)) {
    $FirstCoinIndex = $CoinSet * $CoinsPerCoinSet
    $LastCoinIndex = ($CoinSet + 1) * $CoinsPerCoinSet - 1
    $CoinsToSend = $UTXOsToConsolidate[$FirstCoinIndex..$LastCoinIndex]
    $TxParameters = @{
        Coins = $CoinsToSend
        DestinationAddress = $DestinationAddress
        WalletName = $WalletName
        Password = $Password
        AccountName = $AccountName
        BaseUri = $BaseUri
        Fee = $Fee
    }
    $Tx = Send-SelectedCoins @TxParameters

    [pscustomobject]@{
        TransactionId = $Tx.transactionId
        DestinationAddress = $TX.outputs | Select-Object -ExpandProperty address
        Amount = $TX.outputs.amount / 1e8
    }
}

$TXs
Start-Sleep -Seconds 2
Write-Host "Sent $(($TXs | Measure-Object -Property Amount -Sum).sum) to  $DestinationAddress" -ForegroundColor DarkGreen
pause
