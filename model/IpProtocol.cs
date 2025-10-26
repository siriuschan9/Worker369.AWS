using System;

namespace Worker369.AWS;

public readonly struct IpProtocol : IComparable, IComparable<IpProtocol>
{
    public int    Number      { get; }
    public string Keyword     { get; }

    public readonly static IpProtocol All    = new(-1, "All");
    public readonly static IpProtocol ICMP   = new(1,  "ICMP");
    public readonly static IpProtocol IGMP   = new(2,  "IGMP");
    public readonly static IpProtocol TCP    = new(6,  "TCP");
    public readonly static IpProtocol UDP    = new(17, "UDP");
    public readonly static IpProtocol ICMPv6 = new(58, "ICMPv6");

    private IpProtocol(int number, string keyword)
    {
        Number  = number;
        Keyword = keyword;
    }

    public override string ToString()
    {
        if (string.IsNullOrEmpty(Keyword))
            return $"{Number}";
        else
            return $"{Number} ({Keyword})";
    }

    public static IpProtocol FromNumber(int number)
    {
        return number switch
        {
            -1 => All,
            1  => ICMP,
            2  => IGMP,
            6  => TCP,
            17 => UDP,
            58 => ICMPv6,
            _  => new IpProtocol(number, string.Empty),
        };
    }

    public static IpProtocol FromString(string number)
    {
        return number switch
        {
            "icmp"   => ICMP,
            "tcp"    => TCP,
            "udp"    => UDP,
            "icmpv6" => ICMPv6,
            _        => FromNumber(Convert.ToInt32(number)),
        };
    }

    public readonly int CompareTo(object obj)
    {
        if (obj is null) return 1;

        return obj is IpProtocol other
            ? CompareTo(other)
            : throw new ArgumentException($"Object is not a {typeof(IpProtocol)}");
    }

    public readonly int CompareTo(IpProtocol other) => Number.CompareTo(other.Number);

    public readonly bool Equals(IpProtocol other) => CompareTo(other) == 0;

    public override readonly int GetHashCode() => Number.GetHashCode();
}

public readonly struct FromPort(int number, bool isIcmp = false)
{
    public int  Number { get; } = number;
    public bool IsIcmp { get; } = isIcmp;

    public override string ToString()
    {
        return IsIcmp ? $"Type {Number}" : $"{Number}";
    }
}

public readonly struct ToPort(int number, bool isIcmp = false)
{
    public int  Number { get; } = number;
    public bool IsIcmp { get; } = isIcmp;

    public override string ToString()
    {
        return IsIcmp ? $"Code {Number}" : $"{Number}";
    }
}