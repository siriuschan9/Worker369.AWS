
function Resolve-PrefixList
{
    [CmdletBinding()]
    [Alias('pl_resolve', 'pl_read')]
    param (
        [Parameter(ParameterSetName = "PrefixListId", Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidatePattern('^pl-([0-9a-f]{8}|[0-9a-f]{17})$')]
        [string]
        $PrefixListId,

        [Parameter(ParameterSetName = "PrefixListName", Position = 0, Mandatory)]
        [string]
        $PrefixListName,

        [int]
        $TargetVersion
    )

    BEGIN
    {
         # For easy pick up.
        $_param_set = $PSCmdlet.ParameterSetName
    }

    PROCESS
    {
        # Use snake_case.
        $_pl_id   = $PrefixListId
        $_pl_name = $PrefixListName
        $_version = $TargetVersion

        # Configure the filter to query the Prefix List.
        $_filter_name  = $_param_set -eq 'PrefixListId' ? 'prefix-list-id' : 'prefix-list-name'
        $_filter_value = $_param_set -eq 'PrefixListId' ? $_pl_id : $_pl_name

        $_filter = [Amazon.EC2.Model.Filter]@{
            Name   = $_filter_name
            Values = $_filter_value
        }

        # Grab the prefix lists first.
        try {
            $_pl_list = Get-EC2ManagedPrefixList -Verbose:$false -Filter $_filter
        }
        catch {
            # Remove caught exception emitted into $Error list.
            Pop-ErrorRecord $_

            # Report error as non-terminating.
            $PSCmdlet.WriteError($_)

            # Exit early.
            return
        }

        try {
            foreach ($_pl in $_pl_list)
            {
                Get-EC2ManagedPrefixListEntry -Verbose:$false $_pl.PrefixListId `
                    -TargetVersion ([int]::Max($_pl.Version, $_version))
                | Select-Object -ExpandProperty Cidr
            }
        }
        catch {
            # Remove caught exception emitted into $Error list.
            Pop-ErrorRecord $_

            # Report error as non-terminating.
            $PSCmdlet.WriteError($_)
        }
    }
}