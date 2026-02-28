using namespace System.Collections
using namespace System.Collections.Generic

function Get-QueryDefinition
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [hashtable]
        $SelectDefinition,

        [Parameter(Mandatory)]
        [hashtable]
        $ViewDefinition,

        [Parameter(Mandatory)]
        [string]
        $View,

        [Parameter()]
        [string]
        $GroupBy,

        [Parameter()]
        [int[]]
        $Sort,

        [Parameter()]
        [int[]]
        $Exclude
    )

    # Use snake case.
    $_select_definition = $SelectDefinition
    $_view_definition   = $ViewDefinition
    $_view              = $View
    $_group_by          = $GroupBy
    $_sort              = $Sort
    $_exclude           = $Exclude

    # Try to get the list of select names.
    $_select_names = $_view_definition[$_view]

    # If Group By is not in the select names, insert it to the select names.
    if (-not [string]::IsNullOrEmpty($_group_by) -and $_group_by -notin $_select_names)
    {
        $_select_names = @($_group_by) + @($_select_names)
    }

    # Exit early if there are no select names to work on
    if ($null -eq $_select_names -or $_select_names.Count -eq 0) { return }

    # Initialize a select list.
    $_select_list = [List[Object]]::new()

    # Build the select list.
    foreach ($_select_name in $_select_names)
    {
        $_select_list.Add(
            @{
                Name       = $_select_name
                Expression = $_select_definition[$_select_name] ?? {}
            }
        )
    }

    # Initialize a sort list.
    $_sort_list  = [List[Object]]::new()

    # Get a list of sortable names (minus the group name). The sort indexes are based on this list.
    $_sort_names = $_select_names | Where-Object { $_ -ne $_group_by }

    # Add group to sort list first. Sort by group is enforced and takes priority over caller-specified indexes.
    if(-not [string]::IsNullOrEmpty($_group_by) -and $_group_by -in $_select_names)
    {
        $_sort_list.Add(
            @{
                Expression = $_group_by;
                Descending = $false
            }
        )
    }

    # Build the sort list using the sort indexes ($_sort) and the name list ($_sort_names).
    for($_i = 0 ; $_i -lt $_sort.Length ; $_i++)
    {
        # Column number is 1-based. Column index is 0-based.
        $_sort_index = [Math]::Abs($_sort[$_i]) - 1

        # Guard against index out of bound.
        if ($_sort_index -ge $_sort_names.Length) { continue }

        # Get the column name.
        $_sort_name = $_sort_names[$_sort_index]

        # Get ascending or descending.
        $_descending = $($_sort[$_i] -lt 0)

        $_sort_list.Add(
            @{
                Expression = "$_sort_name"
                Descending = $_descending
            }
        )
    }

    # Initialize a project list.
    $_project_list  = [List[Object]]::new()

    # Get a list of projectable names (minus the group name). The exclude indexes are based on this list.
    $_project_names = $_select_names | Where-Object { $_ -ne $_group_by }

    # Add the group property to the project list first.
    if (-not [string]::IsNullOrEmpty($_group_by) -and $_group_by -in $_select_names)
    {
        $_project_list.Add($_group_by)
    }

    # Add all properties not in the exclude list to the project list.
    for ($_i = 0 ; $_i -lt $_project_names.Length; $_i++)
    {
        if (($_i + 1) -notin $_exclude)
        {
            $_project_list.Add($_project_names[$_i])
        }
    }

    @($_select_list, $_sort_list, $_project_list)
}