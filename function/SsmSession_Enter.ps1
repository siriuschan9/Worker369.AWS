function Enter-SsmSession
{
    [CmdletBinding(DefaultParameterSetName = 'Hostname')]
    param (
        [Parameter(ParameterSetName = 'InstanceId')]
        [ValidatePattern('^vpc-[0-9a-f]{17}$')]
        [string]
        $InstanceId
    )

    $_instance_id = $InstanceId

    try {

    }
    catch {
        # Remove caught exception emitted into $Error list.
        Pop-ErrorRecord $_

        # Re-throw caught exception.
        $PSCmdlet.ThrowTerminatingError($_)
    }

}