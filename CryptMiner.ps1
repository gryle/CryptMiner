#************************************************************************************************************************************************************************************
#************************************************************************************************************************************************************************************
#************************************************************************************************************************************************************************************

function set_ConsolePosition ([int]$x,[int]$y) { 
        # Get current cursor position and store away 
        $position=$host.ui.rawui.cursorposition 
        # Store new X Co-ordinate away 
        $position.x=$x
        $position.y=$y
        # Place modified location back to $HOST 
        $host.ui.rawui.cursorposition=$position
        remove-variable position
        }

#************************************************************************************************************************************************************************************
#************************************************************************************************************************************************************************************
#************************************************************************************************************************************************************************************

function Get_ConsolePosition ([ref]$x,[ref]$y) { 

    $position=$host.ui.rawui.cursorposition 
    $x.value=$position.x
    $y.value=$position.y
    remove-variable position

}
        


   
#************************************************************************************************************************************************************************************
#************************************************************************************************************************************************************************************
#************************************************************************************************************************************************************************************
function Print_Horizontal_line ([string]$Tittle) { 

       $Width = $Host.UI.RawUI.WindowSize.Width
       $A=$tittle.Length

       if ($Tittle -eq "") {$str = "-" * $Width}
             else {
                $str = ("-" * ($Width/2 - ($tittle.Length/2) - 4)) +"  "+$Tittle+"  " 
                $str += "-" * ($Width-$str.Length)
             }
       $str | Out-host
   
}

   
#************************************************************************************************************************************************************************************
#************************************************************************************************************************************************************************************
#************************************************************************************************************************************************************************************

function set_WindowSize ([int]$Width,[int]$Height) { 
    #zero not change this axis
    

    $pshost = Get-Host
    $RawUI = $pshost.UI.RawUI

    #Buffer must be always greater than windows size
  
    $BSize = $Host.UI.RawUI.BufferSize
    if ($Width -ne 0 -and $Width -gt $BSize.Width) {$BSize.Width=$Width} 
    if ($Height -ne 0 -and $Height -gt $BSize.Height) {$BSize.Width=$Height} 
    
    $Host.UI.RawUI.BufferSize= $BSize


    $WSize = $Host.UI.RawUI.WindowSize
    if ($Width -ne 0) {$WSize.Width =$Width}
    if ($Height -ne 0) {$WSize.Height =$Height}

    $Host.UI.RawUI.WindowSize= $WSize
    
}

#************************************************************************************************************************************************************************************
#************************************************************************************************************************************************************************************
#************************************************************************************************************************************************************************************


Function WriteLog ($Message,$LogFile,$SendToScreen) {
    
     if ($message -ne $null -and $message -ne "") {

            $M=[string](get-date)+"...... "+$Message
            $LogFile.WriteLine($M)
            
            if ($SendToScreen) { $Message | out-host}
        }
}


Function Average($array)
{
    $RunningTotal = 0;
    foreach($i in $array){
        $RunningTotal += $i
    }
    return ([decimal]($RunningTotal) / [decimal]($array.Length));
}

Function AverageProfitChart($array)
{
    $RunningTotal = 0;
    foreach($obj in $array){
        $RunningTotal += $obj[1]
    }
    return ([decimal]($RunningTotal) / [decimal]($array.Length));
}

function get_config {


    $content=[pscustomobject]@{}


    Get-Content CryptMiner.cfg | Where-Object {$_ -like "@@*"} | ForEach-Object {
        $content |add-member (($_ -split '=')[0] -replace '@@','') (($_ -split '=')[1])
    }

    $content
}

function get_pools($file) {

    $configTxt = Get-Content -Path $file -Raw
    $configTxt = "{" + $configTxt + "}"
    $configTxt = $configTxt -replace '(?s)//.*?(\r\n?|\n)|/\*.*?\*/',""
    $configTxt = $configTxt -replace '(?s),(\s*)\]', '$1]'
    $configTxt = $configTxt -replace '(?s),(\s*)}', '$1}'
    $config = ConvertFrom-Json $configTxt
    $pools = $config | Select-Object  -ExpandProperty pool_list

    $pools
}

$logname=".\Logs\$(Get-Date -Format "yyyy-MM-dd_HH-mm-ss").txt"
Start-Transcript $logname   #for start log msg
Stop-Transcript
$LogFile= [System.IO.StreamWriter]::new( $logname,$true )
$LogFile.AutoFlush=$true

try {set_WindowSize 120 25  } catch {}

$config=get_config

$Pools = @()

$NHEnabled = $false
$NHPay = 0
$Divisor = 1000000000
$Hashrate = [double] $config.HASHRATE
$NewPool = ""
$NewPay = 0
$LastPool = ""
$LastPay = 0
$CryptUnitHashMult = [int] $config.CRYPTUNIT_HASH_MULTIPLIER
$NHCorrection = 1
$PercentageToChange = 1 + [double] $config.PERCENTTOSWITCH / 100
$LoopDelay = [int] $config.REFRESHINTERVAL
$NextInterval = [int] $config.INTERVAL_MIN
$AverageSamples = [int] $config.PROFIT_AVERAGE_SAMPLES
if ($AverageSamples -lt 1) {$AverageSamples = 1}

$XmrStakPools=get_pools $config.XMR_STAK_POOLS_FILE
$Coins = Get-Content Coins.json | ConvertFrom-Json


foreach ($Coin in $Coins) {
	$poolAddress = $coin.PoolAddress
	if ($poolAddress -eq $null) { $poolAddress = $Coin.Coin }
	$Pool = $XmrStakPools | Where-Object  { $_.pool_address -match $poolAddress }
	if ($Pool -ne $null) {
		$correction = $coin.ProfitFactor
		if ($correction -eq $null -or $correction -eq "") { $correction = 1 }
		$interval = $coin.Interval
		if ($interval -eq $null -or $interval -eq "") { $interval = $config.INTERVAL_DEFAULT }
		$statsAPI = $coin.StatsAPI
		$Pools +=[pscustomobject]@{"coin" = $Coin.Coin;"pool" = $Pool.pool_address;"statsAPI" = $statsAPI; "correction" = [double] $correction; "interval" = [int] $interval; "earnings" = @(); avgEarning = 0; avgEarningCorrected = 0 };
		if ($coin.Coin -eq "NICEHASH") { $NHEnabled = $true; $NHCorrection = $correction }
	}	
}

writelog ($Pools) $logfile $false

$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
    
$cookie = New-Object System.Net.Cookie 
    
$cookie.Name = "userhashrate"
$cookie.Value = $Hashrate * $CryptUnitHashMult
$cookie.Domain = "www.cryptunit.com"

$session.Cookies.Add($cookie);

$DolarBTCvalue = 9000;

$FirstLoopExecution=$True   
$LoopStarttime=Get-Date

while(1 -eq 1) {
	if ($NHEnabled) {
		#Call api to local currency conversion
		try {
			$CDKResponse = Invoke-WebRequest "https://api.coindesk.com/v1/bpi/currentprice.json" -UseBasicParsing -TimeoutSec 10 | ConvertFrom-Json | Select-Object -ExpandProperty BPI
			#writelog "Coindesk api was responsive.........." $logfile $true
			$DolarBTCvalue = [double]$CDKResponse.usd.rate
		
			writelog ("Dollar/BTC: $DolarBTCvalue") $logfile $false
		} 
			
		catch {
			writelog ("Coindesk api not responding, not possible/deactuallized local coin conversion..........") $logfile $true
			}


		try {
			$Request = Invoke-WebRequest "https://api.nicehash.com/api?method=simplemultialgo.info" -UseBasicParsing -timeoutsec 10 | ConvertFrom-Json 
			$Request = $Request |Select-Object -expand result |Select-Object -expand simplemultialgo | Where-Object {$_.algo -eq 22}

			if ($Request -ne $null) {
				$NHPool = $Pools | Where-Object  {$_.coin -eq "NICEHASH" }
				$NHPay = [double]($Request.paying) * $Hashrate / $Divisor * $DolarBTCvalue
				$NHPool.avgEarning = $NHPay
				$NHPool.avgEarningCorrected = $NHPool.avgEarning * $NHPool.Correction
				if ($NHPool.pool -eq $lastpool) { $LastPay = $NHPool.avgEarningCorrected }
				writelog ("Nicehash pays $NHPay") $logfile $false
			}
		}
		catch {
				writelog ('Nicehash API NOT RESPONDING...') $logfile $true
		}
	}
	
	try {
		$page = Invoke-WebRequest -Uri "https://www.cryptunit.com/?order=price" -UseBasicParsing -WebSession $session -TimeoutSec 10
		$html = $page.Content 
		$regex2 = '(?s)\((\w+)\)<\/h3>.*?Daily earnings.*?([\d\.]+)<em>'
		$matches = $html | Select-String $regex2 -AllMatches | Select -Expand Matches 
		ForEach ($match in $matches) {
			$coin = $match.Groups[1].Value
			$earn = [double]($match.Groups[2].Value) / $CryptUnitHashMult
			$CoinPools = $Pools | Where-Object {$_.coin -eq $coin}
			if ($CoinPools -ne $null) {
				$earnings = $CoinPools.earnings
				if ($CoinPools.earnings.Count -ge $AverageSamples) { $earnings = $CoinPools.earnings[1..$AverageSamples] }
				$earnings += $earn
				$CoinPools.avgEarning = Average($earnings)
				$CoinPools.avgEarningCorrected = $CoinPools.avgEarning * $CoinPools.Correction
				$CoinPools.earnings = $earnings
				writelog ($CoinPools) $logfile $false
				if ($CoinPools.pool -eq $lastpool) { $LastPay = $CoinPools.avgEarningCorrected }
			}
		}
	}		
	catch {
		writelog ('CryptUnit NOT RESPONDING...') $logfile $true
	}
	if ( $FirstLoopExecution -or ((Get-Date) -ge ($LoopStarttime.AddSeconds($NextInterval))) ) {
		$CoinPools = $Pools | Where-Object {$_.statsAPI -ne $null}
		ForEach ($CoinPool in $CoinPools) {
			try {
				$req = Invoke-WebRequest $CoinPool.StatsAPI -UseBasicParsing -timeoutsec 10
				$json = $req | ConvertFrom-Json
				$profit3 = $json|Select-Object -ExpandProperty charts | Select-Object -ExpandProperty profit3			
				if ($profit3.Count -gt $AverageSamples) { $profit3 = $profit3[($profit3.Count-$AverageSamples)..($profit3.Count)] }
				$CoinPool.avgEarning = [decimal](AverageProfitChart($profit3)) * $hashrate / 1000
				$CoinPool.avgEarningCorrected = $CoinPool.avgEarning * $CoinPool.Correction
				if ($CoinPool.pool -eq $lastpool) { $LastPay = $CoinPool.avgEarningCorrected }
			}
			catch {
				writelog ("StatsAPI NOT RESPONDING...") $logfile $true
			}
		}
	
		try {
			$Pools = $Pools | Sort-Object avgEarningCorrected -Descending
			
			$bestpool = $pools[0]
		
			$NewPool = $bestpool.pool
			$NewPay = $bestpool.avgEarningCorrected
			#writelog ($CoinPools.pool)  $logfile $false

			if ($NewPay -lt ($LastPay * $PercentageToChange) -or ($NewPool -eq $LastPool)) {
				writelog ("Keeping old pool") $logfile $false
				$NextInterval = [int] $config.INTERVAL_MIN
				$NewPool = $LastPool
			} else {
				writelog ("Switching to pool $NewPool") $logfile $false
				$NextInterval = $bestpool.Interval
			}
			writelog ("New pool: $NewPool Pays (corrected): $NewPay") $logfile $false
			try {
				foreach($Url in $Config.XMR_STAK_URLS -split ",") {
					writelog ($Url) $logfile $false
					$Result = Invoke-WebRequest ($Url + "?pool=$NewPool") -UseBasicParsing -TimeoutSec 10
				}
				$LastPool = $NewPool
				$LoopStarttime=Get-Date
			} catch {
				writelog ('XMR-STAK NOT RESPONDING...') $logfile $false
			}
		}
		catch {
			writelog ('Error setting new pool') $logfile $true
		}
	}

	Clear-Host
	#display interval
	$TimetoNextInterval= NEW-TIMESPAN (Get-Date) ($LoopStarttime.AddSeconds($NextInterval))
	$TimetoNextIntervalSeconds=($TimetoNextInterval.Hours*3600)+($TimetoNextInterval.Minutes*60)+$TimetoNextInterval.Seconds
	if ($TimetoNextIntervalSeconds -lt 0) {$TimetoNextIntervalSeconds = 0}

	set_ConsolePosition ($Host.UI.RawUI.WindowSize.Width-31) 2
	"|  Next Interval:  $TimetoNextIntervalSeconds secs..." | Out-host
	set_ConsolePosition 0 0

	#display header     
	Print_Horizontal_line  "CryptMiner"  
	Print_Horizontal_line
	"  (E)nd Interval   (Q)uit" | Out-host
	Print_Horizontal_line

	$Pools | Format-Table (
            @{Label = "Coin"; Expression = {$_.Coin}},   
            @{Label = "Pool"; Expression = {$_.Pool}},
            @{Label = "Correction"; Expression = {($_.correction * 100).tostring("n1") + "%"} ; Align = 'right'},   
            @{Label = "Last Earning"; Expression = {$_.earnings.Get($_.earnings.Count - 1).tostring("n2") + "$"} ; Align = 'right'},   
            @{Label = "Avg. Earning"; Expression = {$_.avgEarning.tostring("n2") + "$"} ; Align = 'right'},   
            @{Label = "Avg. Earning Corrected"; Expression = {$_.avgEarningCorrected.tostring("n2") + "$"} ; Align = 'right'}   
        ) | out-host
	

	$FirstLoopExecution=$False

	
	Start-Sleep $LoopDelay

}
