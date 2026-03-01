$_cmd_lookup = @{
    BucketName = @(
        'Show-S3Bucket', 'Show-S3Policy',
        'Show-S3Folder', 'Show-S3FileContent', 'Show-S3FileVersion',
        'Get-S3File',
        'Clear-S3Bucket',
        'Enable-S3BucketVersioning', 'Disable-S3BucketVersioning',
        'Enable-S3BucketKey', 'Disable-S3BucketKey',
        'Set-S3Encryption',
        'Set-S3BlockedEncryption', 'Clear-S3BlockedEncryption'
    )
    Folder = @(
        'Show-S3Folder', 'Show-S3FileVersion'
    )
    Key = @(
        'Show-S3FileContent', 'Get-S3File'
    )
    KmsKeyArn = @(
        'Set-S3Encryption'
    )
    Path = @(
        'Remove-S3File'
    )
    ServerSideEncryptionMethod = @(
        'Edit-S3BucketEncryption'
    )
    VersionId = @(
        'Remove-S3File'
    )
}

# BucketName
Register-ArgumentCompleter -ParameterName 'BucketName' -CommandName $_cmd_lookup['BucketName'] -ScriptBlock {

    param(
        $_command_name,
        $_parameter_name,
        $_word_to_complete,
        $_command_ast,
        $_fake_bound_parameters
    )

    $_bucket_list = Get-S3Bucket -Verbose:$false -Select Buckets.BucketName

    if (-not $_bucket_list) { return }

    $_bucket_list | Where-Object { $_ -like "$_word_to_complete*" } | ForEach-Object {

        [System.Management.Automation.CompletionResult]::new(
            $_,               # completionText
            $_,               # listItemText
            'ParameterValue', # resultType
            $_                # toolTip
        )
    }
}

# Folder
Register-ArgumentCompleter -ParameterName 'Folder' -CommandName $_cmd_lookup['Folder'] -ScriptBlock {

    param(
        $_command_name,
        $_parameter_name,
        $_word_to_complete,
        $_command_ast,
        $_fake_bound_parameters
    )

    $_bucket = $_fake_bound_parameters['BucketName']
    $_folder = $_fake_bound_parameters['Folder']

    if ([string]::IsNullOrEmpty($_bucket)) { return }

    Get-S3Object -Verbose:$false -Select * -BucketName $_bucket -Prefix $_folder -Delimiter '/' |
    Select-Object -ExpandProperty CommonPrefixes | Where-Object {$_ -like "$_word_to_complete*" } |
    ForEach-Object {

        [System.Management.Automation.CompletionResult]::new(
            $_,               # completionText
            $_,               # listItemText
            'ParameterValue', # resultType
            $_                # toolTip
        )
    }
}

# Key
Register-ArgumentCompleter -ParameterName 'Key' -CommandName $_cmd_lookup['Key'] -ScriptBlock {

    param(
        $_command_name,
        $_parameter_name,
        $_word_to_complete,
        $_command_ast,
        $_fake_bound_parameters
    )

    $_bucket = $_fake_bound_parameters['BucketName']
    $_key    = $_fake_bound_parameters['Key']

    if ([string]::IsNullOrEmpty($_bucket)) { return }

    $_response = Get-S3Object -Verbose:$false -Select * -BucketName $_bucket -Prefix $_key -Delimiter '/'

    $_response | Select-Object -ExpandProperty CommonPrefixes |
    Where-Object {$_ -like "$_word_to_complete*"} | ForEach-Object {

        [System.Management.Automation.CompletionResult]::new(
            $_,               # completionText
            $_,               # listItemText
            'ParameterValue', # resultType
            $_                # toolTip
        )
    }

    $_response | Select-Object -ExpandProperty S3Objects |
    Where-Object Key -Like "$_word_to_complete*" | ForEach-Object {

        [System.Management.Automation.CompletionResult]::new(
            $_.Key,           # completionText
            $_.Key,           # listItemText
            'ParameterValue', # resultType
            $_.Key            # toolTip
        )
    }
}

# KmsKeyArn
Register-ArgumentCompleter -ParameterName 'KmsKeyArn' -CommandName $_cmd_lookup['KmsKeyArn'] -ScriptBlock {

    param(

    $_command_name,
        $_parameter_name,
        $_word_to_complete,
        $_command_ast,
        $_fake_bound_parameters
    )

    $_all_key_list    = Get-KMSKeyList -Verbose:$false
    $_all_alias_list  = Get-KMSAliasList -Verbose:$false
    $_aws_alias_list  = $_all_alias_list | Where-Object AliasName -Like 'alias/aws/*'
    $_aws_key_id_list = $_aws_alias_list | Select-Object -ExpandProperty TargetKeyId

    # 1. A list of all CMK Key ARN.
    $_cmk_key_arn_list = `
        @($_all_key_list | Where-Object KeyId -NotIn $_aws_key_id_list | Select-Object -ExpandProperty KeyArn)

    # 2. A list of all CMK alias ARN.
    $_cmk_alias_arn_list = `
        @($_all_alias_list | Where-Object AliasName -NotLike 'alias/aws/*' | Select-Object -ExpandProperty AliasArn)

    # 3. Default S3 KMS Key ARN.
    $_s3_key_arn_list = `
        @($_aws_alias_list | Where-Object AliasName -eq 'alias/aws/s3') | Select-Object -ExpandProperty AliasArn

    # Join all 3 lists and generate autocomplete items,
    $_cmk_key_arn_list + $_cmk_alias_arn_list + $_s3_key_arn_list | Select-Object -Unique | Where-Object {
        $_ -like "$_word_to_complete*"
    } `
    | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new(
            $_,               # completionText
            $_,               # listItemText
            'ParameterValue', # resultType
            $_                # toolTip
        )
    }
}

# VersionId
Register-ArgumentCompleter -ParameterName 'VersionId' -CommandName $_cmd_lookup['VersionId'] -ScriptBlock {

    param(
        $_command_name,
        $_parameter_name,
        $_word_to_complete,
        $_command_ast,
        $_fake_bound_parameters
    )

    $_bucket = $_fake_bound_parameters['BucketName']
    $_key    = $_fake_bound_parameters['Key']

    if ([string]::IsNullOrEmpty($_bucket)) { return }
    if ([string]::IsNullOrEmpty($_key)) { return }

    $_dim   = [System.Management.Automation.PSStyle]::Instance.Dim
    $_reset = [System.Management.Automation.PSStyle]::Instance.Reset

    Get-S3Version -Verbose:$false -BucketName $_bucket -Prefix $_key -Delimiter '/' |
    Select-Object -ExpandProperty Versions |
    Where-Object {$_.VersionId -like "$_word_to_complete*"} | ForEach-Object {

        $_version_id = $_.VersionId
        $_date = $_.LastModified
        $_is_delete_marker = $_.IsDeleteMarker ? 'd' : '_'
        $_is_latest = $_.IsLatest ? 'l' : '_'

        $_display_item = '{0,-32} {1}' -f $_version_id, "$_dim| $($_date):$($_is_delete_marker):$($_is_latest)$_reset"

        [System.Management.Automation.CompletionResult]::new(
            $_version_id,     # completionText
            $_display_item,   # listItemText
            'ParameterValue', # resultType
            $_display_item    # toolTip
        )
    }
}

# ServerSideEncryptionMethod
Register-ArgumentCompleter `
    -ParameterName 'ServerSideEncryptionMethod' -CommandName $_cmd_lookup['ServerSideEncryptionMethod'] -ScriptBlock {

    param(
        $_command_name,
        $_parameter_name,
        $_word_to_complete,
        $_command_ast,
        $_fake_bound_parameters
    )

    [Amazon.S3.ServerSideEncryptionMethod].GetFields() | ForEach-Object {
        $_.GetValue($null).Value
    } `
    | Where-Object {
        -not [string]::IsNullOrEmpty($_) -and $_ -like "$_word_to_complete*"
    } `
    | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new(
            $_,               # completionText
            $_,               # listItemText
            'ParameterValue', # resultType
            $_                # toolTip
        )
    }
}