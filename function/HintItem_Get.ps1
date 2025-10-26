function Get-HintItem
{
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(ValueFromPipeline)]
        [Object]
        $InputObject,

        [Parameter(Mandatory)]
        [String]
        $IdPropertyName,

        [Parameter(Mandatory)]
        [String]
        $TagPropertyName,

        [Parameter(Mandatory)]
        [int]
        $Alignment
    )

    PROCESS
    {
        if (-not $InputObject) { return }

        # Use snake_case.
        $_input_object      = $InputObject
        $_id_property_name  = $IdPropertyName
        $_tag_property_name = $TagPropertyName
        $_alignment         = $Alignment

        try{
            # Retrieve the resource ID and name tag and saves them to local variables.
            $_resource_id   = $_input_object.$_id_property_name
            $_resource_name = $_input_object.$_tag_property_name |
                Where-Object Key -eq 'Name' |
                Select-Object -ExpandProperty Value

            [HintItem]::new($_resource_id, $_resource_name, $_alignment)
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