function Get-HintItem
{
    [CmdletBinding(DefaultParameterSetName = 'NameTag')]
    [OutputType([string])]
    param (
        [Parameter(ValueFromPipeline)]
        [Object]
        $InputObject,

        [Parameter(Mandatory)]
        [string]
        $IdPropertyName,

        [Parameter(ParameterSetName ='NameTag', Mandatory)]
        [string]
        $TagPropertyName,

        [Parameter(ParameterSetName ='NameProperty', Mandatory)]
        [string]
        $NamePropertyName,

        [Parameter(Mandatory)]
        [int]
        $Alignment
    )

    BEGIN
    {
        # For easy pick up
        $_param_set = $PSCmdlet.ParameterSetName
    }

    PROCESS
    {
        if (-not $InputObject) { return }

        # Use snake_case.
        $_input_object       = $InputObject
        $_id_property_name   = $IdPropertyName
        $_tag_property_name  = $TagPropertyName
        $_name_property_name = $NamePropertyName
        $_alignment          = $Alignment

        try{
            # Retrieve the resource ID and name tag and saves them to local variables.
            $_resource_id   = $_input_object.$_id_property_name

            if ($_param_set -eq 'NameProperty') {
                $_resource_name = $_input_object.$_name_property_name
            }
            else {
                $_resource_name = $_input_object.$_tag_property_name `
                    | Where-Object Key -eq 'Name' `
                    | Select-Object -ExpandProperty Value
            }

            [Worker369.AWS.HintItem]::new($_resource_id, $_resource_name, $_alignment)
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