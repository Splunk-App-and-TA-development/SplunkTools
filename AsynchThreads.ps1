﻿Import-Module PoshRSJob

<#
Objective:
Run a script having parameters as thread on an interval; show results from all scripts
#>

# Define significant variables influencing job control
$JobName = "ewstest"
$OutputFile = "$($env:TEMP)\$($JobName).log"
$ScriptBlockSource = "C:\apps\ComplexScript.ps1"

# build list of target hosts
$TargetHosts = 1..20 | %{"host$($_)"}

function get-durationMsUntilNextMinute {
    $NextStartDate = [datetime](Get-Date).AddMinutes(1).ToString("HH:mm")
    $NextStartDateTotalMS = (New-TimeSpan -End $NextStartDate).TotalMilliseconds
    return $NextStartDateTotalMS
}

function format-splunktime {
    param (
        [parameter(Mandatory=$false)][datetime]$inputDate=(Get-Date)
    )

    $inputDateString = $inputDate.ToString('MM-dd-yyyy HH:mm:ss zzzz')
    $inputDateParts = $inputDateString -split " "
    $inputDateZone = $inputDateParts[2] -replace ":",""
    $outputDateString  = "$($inputDateParts[0]) $($inputDateParts[1]) $($inputDateZone)"
    return $outputDateString
}

function format-splunkLogFromObject {
    param (
        [parameter(Mandatory=$true)]$object
    )

    $Properties = ($object | get-member -MemberType NoteProperty).Name
    $Records = @()
    foreach ($item in $object) {
        $Record = "$(format-splunktime -inputDate $item.StartDate) -"

        foreach ($Property in $Properties) {
            $Record += " $($Property)=`"$($item.$($property))`""
        }
        $Records += $Record
    }

    return $Records
}

# get script to run into into scriptblock object
if (Test-Path -Path $ScriptBlockSource) {
    $ScriptBlock = (Get-Command $ScriptBlockSource).ScriptBlock
} else {
    Write-Host "Unable to find required file: $($ScriptBlockSource)."
    exit
}

# wait until top of next minute
$durationWait = get-durationMsUntilNextMinute
write-host "$(format-splunktime) - waiting until top of next minute..."
Start-Sleep -Milliseconds $durationWait

# loop forever
while ($true)
{
    # invoke script as thread for each host
    foreach ($TargetHost in $TargetHosts) { 
        $RSJob = Start-RSJob -Name $JobName -ArgumentList @($TargetHost) -ScriptBlock $ScriptBlock 
    }

    # wait for all of the threads to complete
    $InterimStatus = Wait-RSJob -Name $JobName -ShowProgress -Timeout 30

    # process each of the job results
    $Report = @()
    $RSJobs = Get-RSJob -Name $jobName 
    foreach ($RSJob in $RSJobs | ?{$_.State -eq "Completed"}) {
        # append thread results to report array
        $Report += $RSJob | Receive-RSJob
        # remove the individual job
        $RsJob | Remove-RSJob  -Force  
    }

    # display count of jobs by state
    $Completed = @($RSJobs | ?{$_.State -eq "Completed"})
    $InComplete = @($RSJobs | ?{$_.State -ne "Completed"})

    # write job results to logfile
    $Summary = $Report | ?{$_.DurationMs -ge 4000}
    $Records = format-splunkLogFromObject -object $Summary
    $Records | set-Content -Path $OutputFile -Force

    # display job status & result highlights
    write-host "$(format-splunktime) - $($completed.count) threads completed.  $($incomplete.count) incomplete. $($summary.count) results exceeded threshold."

    # wait until top of next minute
    Start-Sleep -Milliseconds (get-durationMsUntilNextMinute)
    
}
