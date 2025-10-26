function Set-DefaultSecurityGroup
{
    [CmdletBinding(DefaultParameterSetName = 'TagName')]
    [Alias('sg_default')]
    param(
        [Parameter(ParameterSetName = 'GroupId', Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]
        $GroupId,

        [Parameter(ParameterSetName = 'TagName', Mandatory, Position = 0)]
        [string]
        $TagName
    )

    BEGIN
    {
        # For easy pick up.
        $_param_set = $PSCmdlet.ParameterSetName
    }

    PROCESS
    {
        # Use snake_case.
        $_tag_name = $TagName
        $_sg_id    = $GroupId

        # Configure the filter to query the Security Group.
        $_filter_name  = $_param_set -eq 'GroupId' ? 'group-id' : 'tag:Name'
        $_filter_value = $_param_set -eq 'GroupId' ? $_sg_id : $_tag_name

        $_filter = [Amazon.EC2.Model.Filter]@{
            Name   = $_filter_name
            Values = $_filter_value
        }

        # Grab the Security Group first.
        try {
            $_sg_list = Get-EC2SecurityGroup -Verbose:$false -Filter $_filter
        }
        catch {
            # Remove caught exception emitted into $Error list.
            Pop-ErrorRecord $_

            # Report error as non-terminating.
            $PSCmdlet.WriteError($_)

            # Exit early.
            return
        }

        # If no Security Groups matched the filter value, exit early.
        if (-not $_sg_list)
        {
            Write-Error "No Security Groups were found for '$_filter_value'."
            return
        }

        # If multiple Security Groups matched the filter value, exit early.
        if ($_sg_list.Count -gt 1)
        {
            Write-Error "Multiple Security Groups were found for '$_filter_value'. It must match exactly one Security Group."
            return
        }

        $_sg = $_sg_list[0]

        # Save the filtered Security Group.
        $script:DefaultSecurityGroup = $_sg

        $_format_sg = $_sg | Get-ResourceString `
            -IdPropertyName 'GroupId' -TagPropertyName 'Tags' -StringFormat IdAndName -PlainText

        Write-Message -Output "You are currently working on $_format_sg."
    }
}

function Get-DefaultSecurityGroup
{
    [CmdletBinding(DefaultParameterSetName = 'None')]
    [OutputType([Amazon.EC2.Model.SecurityGroup], ParameterSetName = 'Raw')]
    [OutputType([string], ParameterSetName = 'None')]
    [Alias('sg_default?')]

    param(
        [Parameter(ParameterSetName = 'Raw')]
        [switch]$Raw
    )

    return $PSCmdlet.ParameterSetName -eq 'Raw' `
        ? $script:DefaultSecurityGroup
        : "$($script:DefaultSecurityGroup | Get-ResourceString -IdPropertyName 'GroupId' -TagPropertyName 'Tags')"
}

function Clear-DefaultSecurityGroup
{
    [CmdletBinding()]
    [Alias('sg_default_clear')]
    param()

    Clear-Variable -Scope Script DefaultSecurityGroup
}

[Amazon.EC2.Model.SecurityGroup]$script:DefaultSecurityGroup = $null