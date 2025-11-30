$_cmd_lookup = @{
    BucketName = @(
        'Show-S3Folder', 'Show-S3FileContent'
    )
    Folder = @(
        'Show-S3Folder'
    )
    Key = @(
        'Show-S3FileContent'
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