# Open Location Code Pascal API

This is the Pascal implementation of the Open Location Code API.

# Usage
```
var
  Lat, Lng: Double;
  PlusCode: String;
begin
  PlusCode := '9F28WXR4+FW';
  if TOpenLocationCode.TryDecode(PlusCode, lat, lng) then
  begin
    PlusCode := TOpenLocationCode.Encode(lat, lng);
    Writeln(PlusCode);
  end;
end;
```
# Authors

* The authors of the Java implementation, on which this is based.
* EZeroDivide
