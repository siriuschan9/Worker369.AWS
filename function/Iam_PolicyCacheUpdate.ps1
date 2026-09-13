function Update-IamPolicyCache
{
    [Alias('iam_policy_cache_update')]
    [CmdletBinding()]
    param (
        [Parameter()]
        [ValidateSet('Local', 'AWS', 'All')]
        [string]
        $Scope = 'All'
    )

    $_cmdlet_name = $PSCmdlet.MyInvocation.MyCommand.Name
    $_scope       = $Scope

    try {
        if ($_scope -in @('All', 'Local'))
        {
            Write-Message -Progress $_cmdlet_name 'Downloading customer-managed policies.'
            $global:IamPolicyCache_Local = Get-IAMPolicyList -Verbose:$false -Scope 'Local' -Select Policies.Arn
        }
        if ($_scope -in @('All', 'AWS'))
        {
            Write-Message -Progress $_cmdlet_name 'Downloading AWS-managed policies.'
            $global:IamPolicyCache_AWS   = Get-IAMPolicyList -Verbose:$false -Scope 'AWS' -Select Policies.Arn
        }
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