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
  KairoLat, KairoLng: Double;
begin
  ShortCode := 'X4HM+MM';
  Olc := TOpenLocationCode.Create(ShortCode);
  KairoLat := 30.0 + 3.0/60;
  KairoLng := 31.0 + 14.0/60;
  Olc := Olc.Recover(KairoLat, KairoLng);
  FullCode := Olc.Code;
  assert(FullCode = '7GXHX4HM+MM');
  Writeln(FullCode);
end;
```

# Authors

* The authors of the Java implementation, on which this is based.
* EZeroDivide
