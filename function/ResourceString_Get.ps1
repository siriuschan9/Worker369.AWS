 using namespace Worker369.AWS

<#
.SYNOPSIS
The cmdlet generates an AWS Resource String object from a raw AWS Object.
The Resource String will output "ID [Name]" when the ToString() method is invoked.
You can also change the output to show only ID only or Name only using the -StringFormat Parameter.

.PARAMETER InputObject
The -InputObject Parameter defines the AWS Resource Object used to generate the Resource String.
This Parameter accepts pipeline inputs. See Example 1.

.PARAMETER IdPropertyName
The -IdPropertyName Parameter defines the Name of the Resource ID property of the Input Object.

.PARAMETER TagPropertyName
The -TagPropertyName Parmater defines the Name of the Tags property of the Input Object.

.PARAMETER StringFormat
The -StringFormat Parameter defines the string format for the resource string. Valid values are
  - Id          : ToString() method will return Resource ID only
  - Name        : ToString() method will return Resource Name only
  - IdAndName   : ToString() nethod will return both Resource ID and Resource Name in the format "ID [Name]"

.PARAMETER PlainText
By default, the "[Name]"" part of "ID [Name]" is styled in the console. Specify -PlainText to disable the styling.
Use -PlainText if the output is redirected to file so that ANSI styling codes are removed.

.EXAMPLE
Get-EC2Vpc | Get-ResourceString -IdPropertyName VpcId -TagPropertyName Tags | Sort-Object

vpc-4567890abcdef0123 [example-1]
vpc-34567890abcdef012 [example-2]
vpc-234567890abcdef01 [example-3]
vpc-1234567890abcdef0 [example-4]

The example retrieves VPC objects and pipes them to Get-ResourceString to generate the resource strings.
The resource strings are further piped to Sort-Object.
By default, the sorting will be based on the Resource Name instead of the Resource ID.
To sort by Resource ID, set [ResourceString]::SortByName = $false

#>
function Get-ResourceString
{
    [CmdletBinding(DefaultParameterSetName = 'NameTag')]
    [OutputType([Worker369.AWS.ResourceString])] # Must be fully qualified - not sure why.
    param (
        [Parameter(ValueFromPipeline)]
        [Object]
        $InputObject,

        [Parameter(Mandatory)]
        [String]
        $IdPropertyName,

        [Parameter(ParameterSetName ='NameTag', Mandatory)]
        [String]
        $TagPropertyName,

        [Parameter(ParameterSetName ='NameProperty', Mandatory)]
        [String]
        $NamePropertyName,

        [Parameter()]
        [Worker369.AWS.ResourceStringFormat]
        $StringFormat,

        [Parameter()]
        [switch]
        $PlainText
    )

    BEGIN
    {
        # For easy pick up
        $_param_set = $PSCmdlet.ParameterSetName

        # Use snake_case.
        $_string_format = $StringFormat
        $_plain_text    = $PlainText.IsPresent

        # Determine the resultant resource preference format.
        $_format = `
            $_string_format `
                ?? $global:ResourceStringPreference `
                    ?? [ResourceStringPreference]::IdAndName
    }

    PROCESS
    {
        if (-not $InputObject) { return }

        # Use snake_case.
        $_input_object       = $InputObject
        $_id_property_name   = $IdPropertyName
        $_tag_property_name  = $TagPropertyName
        $_name_property_name = $NamePropertyName

        try{
            # Retrieve the resource ID and name tag and saves them to local variables.
            $_resource_id   = $_input_object.$_id_property_name

            if ($_param_set -eq 'NameProperty') {
                $_resource_name = $_input_object.$_name_property_name
            }
            else {
                $_resource_name = $_input_object.$_tag_property_name |
                    Where-Object Key -eq 'Name' |
                    Select-Object -ExpandProperty Value
            }

            [ResourceString]::new($_resource_id, $_resource_name, $_format, $_plain_text)
        }
        catch
        {
            # Remove caught exception emitted into $Error list.
            Pop-ErrorRecord $_

            # Report error as non-terminating.
            $PSCmdlet.WriteError($_)
        }
    }
}