# Open Location Code Pascal API

This is the Pascal implementation of the Open Location Code API.

# Usage

Convert Plus Code to coordinates and back
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
Get full code from short code and reference location
```
var
  ShortCode, FullCode: String;
  Olc: TOpenLocationCode;
  CairoLat, CairoLng: Double;
begin
  ShortCode := 'X4HM+MM'; // pyradmids of Giza near Cairo
  Olc := TOpenLocationCode.Create(ShortCode);
  CairoLat := 30.0 + 3.0/60;
  CairoLng := 31.0 + 14.0/60;
  Olc := Olc.Recover(CairoLat, CairoLng);
  FullCode := Olc.Code;
  assert(FullCode = '7GXHX4HM+MM');
  Writeln(FullCode);
end;
```

# Authors

* The authors of the Java implementation, on which this is based.
* EZeroDivide
