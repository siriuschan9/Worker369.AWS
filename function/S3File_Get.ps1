function Get-S3File
{
    [Alias('s3_get')]
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 0)]
        [string]
        $BucketName,

        [Parameter(Mandatory, Position = 1, ValueFromPipeline)]
        [string]
        $Key,

        [Parameter(Position = 2)]
        [string]
        $Path
    )

    PROCESS
    {
        # Use snake_case.
        $_bucket_name = $BucketName
        $_key         = $Key
        $_path        = [string]::IsNullOrEmpty($Path) ? ($_key -split '/')[-1] : $Path

        try {
            $_result = Read-S3Object -Verbose:$false $_bucket_name $_key $_path
            $_result.FullName
        }
        catch {
            # Remove caught exception emitted into $Error list.
            Pop-ErrorRecord $_

            # Report error as non-terminating.
            $PSCmdlet.WriteError($_)

            # Exit this PROCESS block early.
            return
        }
    }
}