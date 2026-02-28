function Remove-S3File
{
    [Alias('s3_rm')]
    [CmdletBinding(DefaultParameterSetName = 'ByKey')]
    param (
        [Parameter(ParameterSetName = 'ByPath', Position = 0, Mandatory)]
        [Parameter(ParameterSetName = 'ByKey', Position = 0, Mandatory)]
        [string]
        $BucketName,

        [Parameter(ParameterSetName = 'ByPath', Position = 1, Mandatory)]
        [string]
        $Path,

        [Parameter(ParameterSetName = 'ByPath')]
        [switch]
        $Recurse,

        [Parameter(ParameterSetName = 'ByPath')]
        [switch]
        $DeleteVersions,

        [Parameter(ParameterSetName = 'ByKey', Position = 2, Mandatory)]
        [string]
        $Key,

        [Parameter(ParameterSetName = 'ByKey', Position = 3)]
        [string]
        $VersionId
    )

    BEGIN
    {
        # For easy pick up later.
        $_param_set = $PSCmdlet.ParameterSetName
        $_cmdlet_name = $PSCmdlet.MyInvocation.MyCommand.Name
    }

    PROCESS
    {
        # Use snake_case.
        $_bucket_name = $BucketName
        $_path = $Path
        $_recurse = $Recurse.IsPresent
        $_delete_versions = $DeleteVersions.IsPresent
        $_key = $Key
        $_version_id = $VersionId

        if ($_param_set -eq 'ByPath')
        {

        }

        if ($_param_set -eq 'ByKey')
        {

        }
    }
}