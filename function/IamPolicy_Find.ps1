function Find-IamPolicy
{
    [CmdletBinding()]
    [Alias('iam_policy_find')]
    param (
        [Parameter()]
        [ValidateSet('Local', 'AWS')]
        [String]
        $Scope = 'Local',

        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [String]
        $Filter,

        [Parameter()]
        [switch]
        $RefreshCache
    )

    BEGIN
    {
        $_cmdlet_name   = $PSCmdlet.MyInvocation.MyCommand.Name
        $_refresh_cache = $RefreshCache.IsPresent
        $_scope         = $Scope

        switch ($_scope)
        {
            'Local'
            {
                if (-not (Get-Variable -Scope Global -ErrorAction SilentlyContinue 'IamPolicyCache_Local')) {
                    New-Variable -Scope Global -Name 'IamPolicyCache_Local' -Value $null
                }
                $_cache = [ref]$global:IamPolicyCache_Local
            }
            'AWS'
            {
                if (-not (Get-Variable -Scope Global -ErrorAction SilentlyContinue 'IamPolicyCache_AWS')) {
                    New-Variable -Scope Global -Name 'IamPolicyCache_AWS' -Value $null
                }
                $_cache = [ref]$global:IamPolicyCache_AWS
            }
        }

        if ($_refresh_cache -or -not $_cache.Value)
        {
            try {
                Write-Message -Progress $_cmdlet_name 'Downloading policies.'
                $_cache.Value = Get-IAMPolicyList -Verbose:$false -Scope $_scope -Select Policies.Arn
            }
            catch {
                # Remove caught exception emitted into $Error list.
                Pop-ErrorRecord $_

                # Report error as non-terminating.
                $PSCmdlet.WriteError($_)

                # Exit early.
                return
            }
        }
    }

    PROCESS
    {
        $_filter = $Filter
        $_cache.Value | Select-String $_filter | Sort-Object
    }
}