﻿Add-Type -AssemblyName PresentationFramework
Add-Type -Path  "$PSScriptRoot\WpfInPowerShell\Toolkit\bin\Debug\Toolkit.dll"


[WpfToolkit.ViewModelBase]::InvokeCommand = $ExecutionContext.InvokeCommand
[WpfToolkit.ViewModelBase]::InitScript = {
    param($self, $PropertyName)
    $self | 
        Add-Member -MemberType ScriptMethod -Name "Set$PropertyName" -Value ([ScriptBlock]::Create("
            param(`$value)
            `$this.'$PropertyName' = `$value
            `$this.OnPropertyChanged('$PropertyName')
        ")) -PassThru | 
        Add-Member -MemberType ScriptMethod -Name "Get$PropertyName" -Value ([ScriptBlock]::Create("
            `$this.'$PropertyName'
        "))
}

[WpfToolkit.ViewModelBase]::BackgroundWorkScript = {
    # gets invoked when a background command is called
    # user passes two scriptblocks
    param ($work, $callback)

    Write-Host work: "{" $work "}"

    [scriptblock]::Create("
        param(`$this, `$o)
        try {
            `$callback = { $callback }
            Write-Debug 'Invoking background task'

            # store view model into hashtable so we can access 
            # it in the target runspace

            # also store the callback that we will invoke via
            # dispatcher when the main work is done
            `$syncHash = [hashtable]::Synchronized(@{ 
                This = `$this
                Object = `$o
                CallBack = `$callback
             })

            `$psCmd = [powershell]::Create()
            `$newRunspace = [RunspaceFactory]::CreateRunspace()
            `$newRunspace.Open()
            
            `$newRunspace.SessionStateProxy.SetVariable('syncHash', `$syncHash) 
            `$psCmd.Runspace = `$newRunspace

            `$sb = [scriptblock]::Create({
                function log (`$string) {
                    `$string | Out-File -FilePath '$PSScriptRoot\log.txt' -Append
                }

                `$this = `$syncHash.This
                `$work = { $work }
            
                function Dispatch (`$ScriptBlock) {
                    `[System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke(`$ScriptBlock)
                }

                # invoke the main work
                try {
                    &`$work `$this `$o
                }
                catch {
                    log `"Invoking work failed with error `$(`$error | Out-String)`"
                }
                try {  
                    [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke({ 
                        function log (`$string) {
                            `$string | Out-File -FilePath '$PSScriptRoot\log.txt' -Append
                        }
                        `$callback = { $callback }
                        &`$callback `$syncHash.This 
                    })
                }
                catch {
                    log `"Invoking callback failed with error `$(`$error | Out-String)`"
                }   
            })
        
            `$psCmd.AddScript(`$sb)
            `$psCmd.BeginInvoke()
        }
        catch {
            log `"Invoking background task failed with error `$(`$error | Out-String)`"
        }    
        ")
}