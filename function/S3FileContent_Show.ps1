function Show-S3FileContent
{
    [CmdletBinding()]
    [Alias('s3_cat')]
    param (
        [Parameter(Mandatory, Position = 0)]
        [string]
        $BucketName,

        [Parameter(Mandatory, Position = 1, ValueFromPipeline)]
        [string]
        $Key,

        [switch]
        $AsByteStream,

        [switch]
        $Raw
    )

    BEGIN
    {
        # Try to get the current region from the shell.
        $_region_endpoint = [Amazon.RegionEndpoint]::GetBySystemName($Global:StoredAWSRegion)
        $_has_region      = $_region_endpoint -ne 'Unknown'

        # If we cannot get valid region, do not continue.
        if (-not $_has_region)
        {
            $_error_record = New-ErrorRecord `
                -ErrorMessage 'Unable to get AWS Region from shell. Use Set-DefaultAWSRegion to set the region.' `
                -ErrorId 'CannotGetCredential' `
                -ErrorCategory NotSpecified

            $PSCmdlet.ThrowTerminatingError($_error_record)
        }

        # Try to get the current credential from the shell.
        $_cred        = $null
        $_store_chain = [Amazon.Runtime.CredentialManagement.CredentialProfileStoreChain]::new()
        $_has_cred    = $_store_chain.TryGetAWSCredentials($Global:StoredAWSCredentials, [ref]$_cred)

         # If we cannot get valid credential, do not continue.
        if (-not $_has_cred)
        {
            $_error_record = New-ErrorRecord `
                -ErrorMessage 'Unable to get AWS Credential from shell. Use Set-AWSCredential to set the credential.' `
                -ErrorId 'CannotGetCredential' `
                -ErrorCategory NotSpecified

            $PSCmdlet.ThrowTerminatingError($_error_record)
        }

        # Initialize one S3 client for all PROCESS invocations.
        $_s3_client = [Amazon.S3.AmazonS3Client]::new($_cred, $_region_endpoint)
    }

    PROCESS
    {
        # Use snake_case.
        $_bucket_name    = $BucketName
        $_key            = $Key
        $_as_byte_stream = $AsByteStream.IsPresent
        $_raw            = $Raw.IsPresent

        # Initialize a S3 request object.
        $_request            = [Amazon.S3.Model.GetObjectRequest]::new()
        $_request.BucketName = $_bucket_name
        $_request.Key        = $_key

        # Try to retrieve the file.
        try {
            $_result          = $_s3_client.GetObjectAsync($_request).GetAwaiter().GetResult()
            $_response_stream = $_result.ResponseStream
        }
        catch {
            # Remove caught exception emitted into $Error list.
            Pop-ErrorRecord $_

            # Report error as non-terminating.
            $PSCmdlet.WriteError($_)

            # Exit this PROCESS block early.
            return
        }

        if ($_as_byte_stream) # Stream bytes.
        {
            # Read in chunks of 64KB.
            $_buffer = New-Object byte[] 64KB

            try {
                while ($true)
                {
                    # Load up the buffer.
                    $_bytes_read = $_response_stream.Read($_buffer, 0, $_buffer.Length)

                    # No more bytes to read. Exit the loop.
                    if ($_bytes_read -le 0) { break }

                    # Buffer not fully filled - print out the filled bytes only.
                    if ($_bytes_read -lt $_buffer.Length) {
                        $_slice = New-Object byte[] $_bytes_read
                        [Array]::Copy($_buffer, 0, $_slice, 0, $_bytes_read)
                        $_slice
                    }
                    # Buffer fully filled - print out the whole buffer.
                    else {
                        $_buffer
                    }

                    if ($PSCmdlet.Stopping) { break }
                }
            }
            catch {
                # Remove caught exception emitted into $Error list.
                Pop-ErrorRecord $_

                # Report error as non-terminating.
                $PSCmdlet.WriteError($_)

                # Exit this PROCESS block early.
                return
            }
            finally {
                if ($_memory_stream) { $_memory_stream.Dispose() }
            }
        }
        else # Stream text.
        {
            if ($_raw) # Prints out one single string.
            {
                try {
                    # Initialize a StreamReader - We shall do UTF-8 only for now. Consider adding Encoding option later.
                    $_reader = [System.IO.StreamReader]::new($_response_stream)

                    # Read once and print out everything
                    $_reader.ReadToEnd()
                }
                catch {
                    # Remove caught exception emitted into $Error list.
                    Pop-ErrorRecord $_

                    # Report error as non-terminating.
                    $PSCmdlet.WriteError($_)

                    # Exit this PROCESS block early.
                    return
                }
                finally {
                    if ($_reader) { $_reader.Dispose() }
                }
            }
            else # Stream line by line.
            {
                try {
                    # Initialize a StreamReader - We shall do UTF-8 only for now. Consider adding Encoding option later.
                    $_reader = [System.IO.StreamReader]::new($_response_stream)

                    while (-not $_reader.EndOfStream)
                    {
                        $_reader.ReadLine()

                        if ($PSCmdlet.Stopping) { break }
                    }
                }
                catch {
                    # Remove caught exception emitted into $Error list.
                    Pop-ErrorRecord $_

                    # Report error as non-terminating.
                    $PSCmdlet.WriteError($_)

                    # Exit this PROCESS block early.
                    return
                }
                finally {
                    if ($_reader) { $_reader.Dispose() }
                }
            }
        }
    }
}