# Open Location Code Pascal API

This is the Pascal implementation of the Open Location Code API.

# Usage

var

  Lat, Lng: Double;
  
  PlusCode: String;
  
begin

  PlusCode := '7GXHX4HM+MM';
  
  TOpenLocationCode.TryDecode(PlusCode, lat, lng);
  
  PlusCode := TOpenLocationCode.Encode(lat, lng);
  
  Writeln(PlusCode);
  
end;

# Development

# Authors

* The authors of the Java implementation, on which this is based.
* EZeroDivide
