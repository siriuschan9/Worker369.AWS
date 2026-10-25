$_cmd_lookup = @{
    VolumeId = @(
        'Disable-EbsDeleteOnTermination'
    )
    VolumeName = @(
        'Disable-EbsDeleteOnTermination'
    )
}

# VolumeId
Register-ArgumentCompleter -ParameterName 'VolumeId' -CommandName $_cmd_lookup['VolumeId'] -ScriptBlock {

    param(
        $_command_name,
        $_parameter_name,
        $_word_to_complete,
        $_command_ast,
        $_fake_bound_parameters
    )

    $_ebs_list = Get-EC2Volume -Verbose:$false -Filter @{
        Name   = 'volume-id'
        Values = "$($_word_to_complete)*"
    }

    if (-not $_ebs_list) { return }

    $_align = `
        $_ebs_list.VolumeId | Select-Object -ExpandProperty Length |
        Measure-Object -Maximum | Select-Object -ExpandProperty Maximum

    $_ebs_list | Get-HintItem -IdPropertyName 'VolumeId' -TagPropertyName 'Tags' -Align $_align |
    Sort-Object | ForEach-Object {

        [System.Management.Automation.CompletionResult]::new(
            $_.ResourceId,    # completionText
            $_,               # listItemText
            'ParameterValue', # resultType
            $_                # toolTip
        )
    }
}

# VolumeName
Register-ArgumentCompleter -ParameterName 'VolumeName' -CommandName $_cmd_lookup['VolumeName'] -ScriptBlock {

    param(
        $_command_name,
        $_parameter_name,
        $_word_to_complete,
        $_command_ast,
        $_fake_bound_parameters
    )

    Get-EC2Volume -Verbose:$false -Filter @{
        Name = 'tag:Name'
        Values = "$_word_to_complete*"
    } |
    Select-Object -ExpandProperty Tags |
    Where-Object Key -eq 'Name' | Select-Object -Unique -ExpandProperty Value |
    Sort-Object | ForEach-Object {

        [System.Management.Automation.CompletionResult]::new(
            $_,               # completionText
            $_,               # listItemText
            'ParameterValue', # resultType
            $_                # toolTip
        )
    }
}