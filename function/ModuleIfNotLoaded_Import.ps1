function Import-ModuleIfNotLoaded
{
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]]
        $Name
    )

    PROCESS
    {
        $_names = $Name

        foreach ($_module_name in $_names)
        {
            try{
                if (-not (Get-Module $_module_name)) {
                    Write-Message -Progress "Importing required module first" "$_module_name"
                    Import-Module $_
                }
            }
            catch {
                # Remove caught exception emitted into $Error list.
                Pop-ErrorRecord $_

                # Throw a new custom error record
                $_error_record = New-ErrorRecord `
                    -ErrorId 'ModuleNotInstalled' `
                    -ErrorMessage (
                        "The specified module is not nstalled. Please install it first. " +
                        "i.e. `"Install-Module $_module_name`".") `
                    -ErrorCategory NotInstalled
                $PSCmdlet.ThrowTerminatingError($_error_record)
            }
        }
    }
}