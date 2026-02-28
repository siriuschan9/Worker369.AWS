<#
.SYNOPSIS
This cmdlet creates a [Amazon.EC2.Model.TagSpecification] object.
If both the -Tag and -Name parameters are not specified, the cmdlet returns nothing.

.PARAMETER ResourceType
The -ResourceType parameter specified the type of the resource in the EC2 family for the TagSpecification object.
Use view the list of valid values. Use the command:
[Amazon.EC2.ResourceType].GetFields().Name

.PARAMETER Tag
The -Tag Parameter specifies an array of [Amazon.EC2.Model.Tag] objects to add to the TagSpecification.

.PARAMETER Name
The -Name Parameter specifies the Name Tag to add to the TagSpecification.
If the -Name paramater is not specified, no Name tag will be created.
If the -Name parameter is null or zero-length, a Name tag will be created with no value.
If the -Tag Parameter includes a 'Name' Tag, it will be overwritten by the -Name Paramater.

.EXAMPLE

#>
function New-TagSpecification
{
    [OutputType([Amazon.EC2.Model.TagSpecification])]
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [Amazon.EC2.ResourceType]
        $ResourceType,

        [Parameter()]
        [Amazon.EC2.Model.Tag[]]
        $Tag,

        [Parameter()]
        [string]
        $Name
    )
    PROCESS
    {
        # Use snake_case.
        $_resource_type = $ResourceType
        $_tag           = $Tag
        $_name          = $Name

        # If the -Name paramater is not specified, no Name tag will be created.
        # If the -Name parameter is null or zero-length, a Name tag will be created with no value.
        $_no_name = -not $PSBoundParameters.ContainsKey('Name')

        # No tags will be created if the -Tag parameter is null or is an empty array.
        $_no_tag = $null -eq $_tag -or $_tag.Length -eq 0

        # If no tags needs to be created, exit early. No TagSpecification object will be returned.
        if ($_no_tag -and $_no_name) { return }

        # Initialize a new TagSpecification object.
        $_tag_specification = [Amazon.EC2.Model.TagSpecification]@{
            ResourceType = $_resource_type
            Tags         = [System.Collections.Generic.List[Amazon.EC2.Model.Tag]]::new()
        }

        # Add the tags to the TagSpecification object.
        if ($_tag) { $_tag_specification.Tags.AddRange($_tag) }

        # Override name tag if name is explicitly specified.
        if ($PSBoundParameters.ContainsKey('Name'))
        {
            $_tag_specification.Tags.RemoveAll({
                $_.Key -eq 'Name'
            }) | Out-Null

            $_tag_specification.Tags.Add(
                [Amazon.EC2.Model.Tag]@{
                    Key   = 'Name'
                    Value = $_name
                }
            )
        }

        # Return the TagSpecification.
        $_tag_specification
    }
}