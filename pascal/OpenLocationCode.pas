unit OpenLocationCode;

interface

uses
  System.SysUtils;

type
  TCodeArea = record
  private
    FSouthLatitude,
    FWestLongitude,
    FNorthLatitude,
    FEastLongitude: Double;
    FLength: Integer;
    function GetCenterLatitude: Double;
    function GetCenterLongitude: Double;
    function GetLatitudeHeight: Double;
    function GetLongitudeWidth: Double;
  public
    constructor Create(ASouthLatitude, AWestLongitude, ANorthLatitude, AEastLongitude: Double; ALength: Integer);
    property SouthLatitude: Double read FSouthLatitude;
    property WestLongitude: Double read FWestLongitude;
    property NorthLatitude: Double read FNorthLatitude;
    property EastLongitude: Double read FEastLongitude;
    property Length: Integer read FLength;
    property CenterLatitude: Double read GetCenterLatitude;
    property CenterLongitude: Double read GetCenterLongitude;
    property LatitudeHeight: Double read GetLatitudeHeight;
    property LongitudeWidth: Double read GetLongitudeWidth;
  end;

  TOpenLocationCode = record
  private
    FCode: String;
  public
    constructor Create(const ACode: String); overload;
    constructor Create(ALatitude, ALongitude: Double; ACodeLength: Integer); overload;
    constructor Create(ALatitude, ALongitude: Double); overload;

    class function Encode(ALatitude, ALongitude: Double; ACodeLength: Integer): String; overload; static;
    class function Encode(ALatitude, ALongitude: Double): String; overload; static;
    class function Decode(const ACode: String): TCodeArea; overload; static;
    function Decode: TCodeArea; overload;

    class function IsFull(const ACode: String): Boolean; overload; static;
    function IsFull: Boolean; overload;
    class function IsShort(const ACode: String): Boolean; overload; static;
    function IsShort: Boolean; overload;
    class function IsPadded(const ACode: String): Boolean; overload; static;
    function IsPadded: Boolean; overload;

    function Shorten(AReferenceLatitude, AReferenceLongitude: Double): TOpenLocationCode;
    function Recover(AReferenceLatitude, AReferenceLongitude: Double): TOpenLocationCode;
    function Contains(ALatitude, ALongitude: Double): boolean;

    class operator Equal(const ALeft, ARight: TOpenLocationCode): Boolean;
    class function IsValidCode(ACode: String): Boolean; static;
    class function IsFullCode(const ACode: String): Boolean; static;
    class function IsShortCode(const ACode: String): Boolean; static;

    property Code: String read FCode;
  private
    class function clipLatitude(ALatitude: Double): Double; static;
    class function normalizeLongitude(ALongitude: Double): Double; static;
    class function computeLatitudePrecision(ACodeLength: Integer): Double; static;
  private
    // Provides a normal precision code, approximately 14x14 meters.
    const CODE_PRECISION_NORMAL = 10;

    // The character set used to encode the values.
    const CODE_ALPHABET = '23456789CFGHJMPQRVWX';

    // A separator used to break the code into two parts to aid memorability.
    const SEPARATOR = '+';

    // The character used to pad codes.
    const PADDING_CHARACTER = '0';

    // The number of characters to place before the separator.
    const SEPARATOR_POSITION = 8;

    // The max number of digits to process in a plus code.
    const MAX_DIGIT_COUNT = 15;

    // Maximum code length using just lat/lng pair encoding.
    const PAIR_CODE_LENGTH = 10;

    // Number of digits in the grid coding section.
    const GRID_CODE_LENGTH = MAX_DIGIT_COUNT - PAIR_CODE_LENGTH;

    // The base to use to convert numbers to/from.
    const ENCODING_BASE = Length(CODE_ALPHABET);

    // The maximum value for latitude in degrees.
    const LATITUDE_MAX = 90;

    // The maximum value for longitude in degrees.
    const LONGITUDE_MAX = 180;

    // Number of columns in the grid refinement method.
    const GRID_COLUMNS = 4;

    // Number of rows in the grid refinement method.
    const GRID_ROWS = 5;

    // Value to multiple latitude degrees to convert it to an integer with the maximum encoding
    // precision. I.e. ENCODING_BASE**3 * GRID_ROWS**GRID_CODE_LENGTH
    const LAT_INTEGER_MULTIPLIER = Int64(8000 * 3125);

    // Value to multiple longitude degrees to convert it to an integer with the maximum encoding
    // precision. I.e. ENCODING_BASE**3 * GRID_COLUMNS**GRID_CODE_LENGTH
    const LNG_INTEGER_MULTIPLIER  = Int64(8000 * 1024);

    // Value of the most significant latitude digit after it has been converted to an integer.
    const LAT_MSP_VALUE: Int64 = Int64(LAT_INTEGER_MULTIPLIER) * ENCODING_BASE * ENCODING_BASE;

    // Value of the most significant longitude digit after it has been converted to an integer.
    const LNG_MSP_VALUE: Int64 = Int64(LNG_INTEGER_MULTIPLIER) * ENCODING_BASE * ENCODING_BASE;
  end;

  EIllegalStateException = class(Exception);

implementation

uses
  System.Math;

{ TCodeArea }

constructor TCodeArea.Create(ASouthLatitude, AWestLongitude, ANorthLatitude,
  AEastLongitude: Double; ALength: Integer);
begin
   FSouthLatitude := ASouthLatitude;
   FWestLongitude := AWestLongitude;
   FNorthLatitude := ANorthLatitude;
   FEastLongitude := AEastLongitude;
   FLength := ALength;
end;

function TCodeArea.GetCenterLongitude: Double;
begin
  Result := (FWestLongitude + FEastLongitude) / 2;
end;

function TCodeArea.GetCenterLatitude: Double;
begin
  Result := (FSouthLatitude + FNorthLatitude) / 2;
end;

function TCodeArea.GetLatitudeHeight: Double;
begin
  Result := FNorthLatitude - FSouthLatitude;
end;

function TCodeArea.GetLongitudeWidth: Double;
begin
  Result := FEastLongitude - FWestLongitude;
end;


{ TOpenLocationCode }

constructor TOpenLocationCode.Create(const ACode: String);
begin
  if not IsValidCode(ACode.ToUpper) then
    raise EArgumentException.Create('The provided code "' + ACode + '" is not a valid Open Location Code.');
  FCode := ACode.ToUpper;
end;

constructor TOpenLocationCode.Create(ALatitude, ALongitude: Double; ACodeLength: Integer);
var
  LRevCode: Array[0..MAX_DIGIT_COUNT] of WideChar;
  LRevCodeLen: Integer;
  LCode: String;
  latVal, lngVal: Int64;
  latDigit, lngDigit: Int64;
  ndx: Integer;
  i: Integer;
begin
  // Limit the maximum number of digits in the code.
  ACodeLength := Min(ACodeLength, MAX_DIGIT_COUNT);
  // Check that the code length requested is valid.
  if (ACodeLength < PAIR_CODE_LENGTH) and ((ACodeLength mod 2 = 1) or (ACodeLength < 4)) then
    raise  EArgumentException('Illegal code length ' + ACodeLength.ToString);

  // Ensure that latitude and longitude are valid.
  ALatitude := ClipLatitude(ALatitude);
  ALongitude := NormalizeLongitude(ALongitude);

  // Latitude 90 needs to be adjusted to be just less, so the returned code can also be decoded.
  if (ALatitude = LATITUDE_MAX) then
      ALatitude := ALatitude - 0.9 * ComputeLatitudePrecision(ACodeLength);

  // Store the code - we build it in reverse and reorder it afterwards.
  LRevCode := '';
  LRevCodeLen := 0;

  // Compute the code.
  // This approach converts each value to an integer after multiplying it by
  // the final precision. This allows us to use only integer operations, so
  // avoiding any accumulation of floating point representation errors.

  // Multiply values by their precision and convert to positive. Rounding
  // avoids/minimises errors due to floating point precision.
  latVal := Trunc(RoundTo((ALatitude + LATITUDE_MAX) * LAT_INTEGER_MULTIPLIER * 1e6, 0) / 1e6);
  lngVal := Trunc(RoundTo((ALongitude + LONGITUDE_MAX) * LNG_INTEGER_MULTIPLIER * 1e6, 0) / 1e6);

  // Compute the grid part of the code if necessary.
  if (ACodeLength > PAIR_CODE_LENGTH) then
  begin
    for i := 0 to GRID_CODE_LENGTH - 1 do
    begin
      latDigit := latVal mod GRID_ROWS;
      lngDigit := lngVal mod GRID_COLUMNS;
      ndx := latDigit * GRID_COLUMNS + lngDigit;
      LRevCode[LRevCodeLen] := CODE_ALPHABET[1+ndx];
      inc(LRevCodeLen);
      latVal := latVal div GRID_ROWS;
      lngVal := lngVal div GRID_COLUMNS;
    end;
  end else
  begin
    latVal := Trunc(latVal / IntPower(GRID_ROWS, GRID_CODE_LENGTH));
    lngVal := Trunc(lngVal / IntPower(GRID_COLUMNS, GRID_CODE_LENGTH));
  end;
  // Compute the pair section of the code.
  for i := 0 to (PAIR_CODE_LENGTH div 2) - 1 do
  begin
    LRevCode[LRevCodeLen] := CODE_ALPHABET[1 + (lngVal mod ENCODING_BASE)];
    inc(LRevCodeLen);
    LRevCode[LRevCodeLen] := CODE_ALPHABET[1 + (latVal mod ENCODING_BASE)];
    inc(LRevCodeLen);
    latVal := latVal div ENCODING_BASE;
    lngVal := lngVal div ENCODING_BASE;
    // If we are at the separator position, add the separator.
    if (i = 0) then
    begin
      LRevCode[LRevCodeLen] := SEPARATOR;
      inc(LRevCodeLen);
    end;
  end;
  // Reverse the code.
  SetLength(LCode, Length(LRevCode));
  for i:= 0 to LRevCodeLen - 1 do
    LCode[LRevCodeLen - i] := LRevCode[i];

  // If we need to pad the code, replace some of the digits.
  if (ACodeLength < SEPARATOR_POSITION) then
  begin
    for i := ACodeLength to SEPARATOR_POSITION - 1 do
    begin
      LCode[i+1] := PADDING_CHARACTER;
    end;
  end;
  Self.FCode := Copy(LCode, 1, Max(SEPARATOR_POSITION, ACodeLength));  //?
end;

constructor TOpenLocationCode.Create(ALatitude, ALongitude: Double);
begin
  Create(ALatitude, ALongitude, CODE_PRECISION_NORMAL);
end;

class function TOpenLocationCode.Decode(const ACode: String): TCodeArea;
begin
  Result := TOpenLocationCode.Create(ACode).Decode;
end;

function TOpenLocationCode.Decode: TCodeArea;
var
  Clean: String;
  latVal, lngVal: Int64;
  latPlaceVal, lngPlaceVal: Int64;
  i: Integer;
  digit, row, col: Integer;
  latitudeLo, longitudeLo,
  latitudeHi, longitudeHi: Double;
begin
  if not IsFullCode(FCode) then
  begin
    raise EIllegalStateException.Create('Method Decode() could only be called on valid full codes, code was "' + FCode + '".');
  end;
  // Strip padding and separator characters out of the code.
  clean := StringReplace(FCode, SEPARATOR, '', []);
  clean := StringReplace(clean, PADDING_CHARACTER, '', [rfReplaceAll]);

  // Initialise the values. We work them out as integers and convert them to doubles at the end.
  latVal := -LATITUDE_MAX * LAT_INTEGER_MULTIPLIER;
  lngVal := -LONGITUDE_MAX * LNG_INTEGER_MULTIPLIER;
  // Define the place value for the digits. We'll divide this down as we work through the code.
  latPlaceVal := LAT_MSP_VALUE;
  lngPlaceVal := LNG_MSP_VALUE;
  i := 0;
  while i < Min(clean.length, PAIR_CODE_LENGTH) do
  begin
    latPlaceVal := latPlaceVal div ENCODING_BASE;
    lngPlaceVal := lngPlaceVal div ENCODING_BASE;
    latVal := latVal + CODE_ALPHABET.indexOf(clean[i+1]) * latPlaceVal;
    lngVal := lngVal + CODE_ALPHABET.indexOf(clean[i+2]) * lngPlaceVal;
    //
    Inc(i, 2);
  end;
  for i := PAIR_CODE_LENGTH to Min(clean.length, MAX_DIGIT_COUNT) - 1 do
  begin
    latPlaceVal := latPlaceVal div GRID_ROWS;
    lngPlaceVal := lngPlaceVal div GRID_COLUMNS;
    digit := CODE_ALPHABET.indexOf(clean[i+1]);
    row := digit div GRID_COLUMNS;
    col := digit mod GRID_COLUMNS;
    latVal := latVal + row * latPlaceVal;
    lngVal := lngVal + col * lngPlaceVal;
  end;
  latitudeLo := Double(latVal) / LAT_INTEGER_MULTIPLIER;
  longitudeLo := lngVal / LNG_INTEGER_MULTIPLIER;
  latitudeHi :=  (latVal + latPlaceVal) / LAT_INTEGER_MULTIPLIER;
  longitudeHi := (lngVal + lngPlaceVal) / LNG_INTEGER_MULTIPLIER;
  Result := TCodeArea.Create(latitudeLo, longitudeLo, latitudeHi, longitudeHi,
    Min(clean.length, MAX_DIGIT_COUNT));
end;

class function TOpenLocationCode.Encode(ALatitude, ALongitude: Double): String;
begin
  Result := TOpenLocationCode.Create(ALatitude, ALongitude).Code;
end;

class function TOpenLocationCode.Encode(ALatitude, ALongitude: Double; ACodeLength: Integer): String;
begin
  Result := TOpenLocationCode.Create(ALatitude, ALongitude, ACodeLength).Code;
end;

function TOpenLocationCode.IsFull: Boolean;
begin
  Result := FCode.indexOf(SEPARATOR) = SEPARATOR_POSITION;
end;

class function TOpenLocationCode.IsFull(const ACode: String): Boolean;
begin
  Result := TOpenLocationCode.Create(ACode).IsFull;
end;

function TOpenLocationCode.IsShort: Boolean;
begin
  Result := (FCode.indexOf(SEPARATOR) >= 0) and (FCode.indexOf(SEPARATOR) < SEPARATOR_POSITION);
end;

class function TOpenLocationCode.IsShort(const ACode: String): Boolean;
begin
  Result := TOpenLocationCode.Create(ACode).IsShort;
end;

function TOpenLocationCode.IsPadded: Boolean;
begin
  Result := FCode.indexOf(PADDING_CHARACTER) >= 0;
end;

class function TOpenLocationCode.IsPadded(const ACode: String): Boolean;
begin
  Result := TOpenLocationCode.Create(ACode).IsPadded;
end;

function TOpenLocationCode.Shorten(AReferenceLatitude, AReferenceLongitude: Double): TOpenLocationCode;
var
  LCodeArea: TCodeArea;
  range: Double;
  i: Integer;
begin
  if not isFull then
  begin
    raise EIllegalStateException.Create('Shorten method could only be called on a full code.');
  end;
  if isPadded then
  begin
    raise EIllegalStateException.Create('Shorten method can not be called on a padded code.');
  end;

  LCodeArea := decode();
  range :=  max(abs(AReferenceLatitude - LCodeArea.CenterLatitude),
                abs(AReferenceLongitude - LCodeArea.CenterLongitude));
    // We are going to check to see if we can remove three pairs, two pairs or just one pair of
    // digits from the code.
    for i := 4 downto 1 do
    begin
      // Check if we're close enough to shorten. The range must be less than 1/2
      // the precision to shorten at all, and we want to allow some safety, so
      // use 0.3 instead of 0.5 as a multiplier.
      if (range < (computeLatitudePrecision(i * 2) * 0.3)) then
      begin
        // We're done.
        Result := TOpenLocationCode.Create(FCode.substring(i * 2));
        exit;
      end;
    end;
    raise EArgumentException.Create('Reference location is too far from the Open Location Code center.');
end;

function TOpenLocationCode.Recover(AReferenceLatitude, AReferenceLongitude: Double): TOpenLocationCode;
var
  digitsToRecover: Integer;
  prefixPrecision: Double;
  recoveredPrefix: String;
  recovered: TOpenLocationCode;
  recoveredCodeArea: TCodeArea;
  recoveredLatitude: double;
  recoveredLongitude: double;
  latitudeDiff: double;
  longitudeDiff: Double;
begin
  if isFull then
  begin
    // Note: each code is either full xor short, no other option.
    exit(Self);
  end;
  AReferenceLatitude := clipLatitude(AReferenceLatitude);
  AReferenceLongitude := normalizeLongitude(AReferenceLongitude);

  digitsToRecover := SEPARATOR_POSITION - code.indexOf(SEPARATOR);
  // The precision (height and width) of the missing prefix in degrees.
  prefixPrecision := Power(ENCODING_BASE, 2 - (digitsToRecover / 2));

  // Use the reference location to generate the prefix.
  recoveredPrefix := TOpenLocationCode.Create(AReferenceLatitude, AReferenceLongitude)
          .Code
          .substring(0, digitsToRecover);
  // Combine the prefix with the short code and decode it.
  recovered := TOpenLocationCode.Create(recoveredPrefix + code);
  recoveredCodeArea := recovered.decode();
  // Work out whether the new code area is too far from the reference location. If it is, we
  // move it. It can only be out by a single precision step.
  recoveredLatitude := recoveredCodeArea.CenterLatitude;
  recoveredLongitude := recoveredCodeArea.CenterLongitude;

  // Move the recovered latitude by one precision up or down if it is too far from the reference,
  // unless doing so would lead to an invalid latitude.
  latitudeDiff := recoveredLatitude - AReferenceLatitude;
  if (latitudeDiff > prefixPrecision / 2) and (recoveredLatitude - prefixPrecision > -LATITUDE_MAX) then
  begin
    recoveredLatitude := recoveredLatitude - prefixPrecision;
  end else if (latitudeDiff < -prefixPrecision / 2) and (recoveredLatitude + prefixPrecision < LATITUDE_MAX) then
  begin
    recoveredLatitude := recoveredLatitude + prefixPrecision;
  end;

  // Move the recovered longitude by one precision up or down if it is too far from the
  // reference.
  longitudeDiff := recoveredCodeArea.CenterLongitude - AReferenceLongitude;
  if (longitudeDiff > prefixPrecision / 2) then
  begin
    recoveredLongitude := recoveredLongitude - prefixPrecision;
  end else if (longitudeDiff < -prefixPrecision / 2) then
  begin
    recoveredLongitude := recoveredLongitude + prefixPrecision;
  end;

  Result := TOpenLocationCode.Create(recoveredLatitude, recoveredLongitude, recovered.Code.length - 1);
end;

function TOpenLocationCode.Contains(ALatitude, ALongitude: Double): Boolean;
var
  LCodeArea: TCodeArea;
begin
  LCodeArea := Decode;
  Result := (LCodeArea.SouthLatitude <= ALatitude) and
            (ALatitude < LCodeArea.NorthLatitude) and
            (LCodeArea.WestLongitude <= ALongitude) and
            (ALongitude < LCodeArea.EastLongitude);
end;

class operator TOpenLocationCode.Equal(const ALeft, ARight: TOpenLocationCode): Boolean;
begin
  Result := ALeft.FCode = ARight.FCode;
end;

class function TOpenLocationCode.IsValidCode(ACode: String): Boolean;
var
  separatorPosition: Integer;
  paddingStarted: Boolean;
  i: Integer;
begin
  if (ACode.length < 2) then
      exit(false);

  ACode := ACode.ToUpper;

  // There must be exactly one separator.
  separatorPosition := ACode.indexOf(SEPARATOR);
  if (separatorPosition = -1) then
      exit(false);

  if (separatorPosition <> ACode.lastIndexOf(SEPARATOR)) then
      exit(false);

  // There must be an even number of at most 8 characters before the separator.
  if (separatorPosition mod 2 <> 0) or (separatorPosition > SEPARATOR_POSITION) then
      exit(false);


  // Check first two characters: only some values from the alphabet are permitted.
  if (separatorPosition = SEPARATOR_POSITION) then
  begin
    // First latitude character can only have first 9 values.
    if (CODE_ALPHABET.indexOf(ACode[1]) > 8) then
      exit(false);

    // First longitude character can only have first 18 values.
    if (CODE_ALPHABET.indexOf(ACode[2]) > 17) then
      exit(false);
  end;

  // Check the characters before the separator.
  paddingStarted := false;
  for i := 0 to separatorPosition - 1 do
  begin
    if (CODE_ALPHABET.indexOf(ACode[1+i]) = -1) and (ACode[1+i] <> PADDING_CHARACTER) then
      // Invalid character.
      exit(false);

    if (paddingStarted) then
    begin
      // Once padding starts, there must not be anything but padding.
      if (ACode[1+i] <> PADDING_CHARACTER) then
        exit(false)
      else if (ACode[1+i] = PADDING_CHARACTER) then
      begin
        paddingStarted := true;
        // Short codes cannot have padding
        if (separatorPosition < SEPARATOR_POSITION) then
          exit(false);
        // Padding can start on even character: 2, 4 or 6.
        if (i <> 2) and (i <> 4) and (i <> 6) then
          exit(false);

      end;
    end;
  end;

  // Check the characters after the separator.
  if (ACode.length > separatorPosition + 1) then
  begin
    if (paddingStarted) then
      exit(false);

    // Only one character after separator is forbidden.
    if (ACode.length = separatorPosition + 2) then
      exit(false);

      for i:= separatorPosition + 1 to ACode.length - 1 do
        if (CODE_ALPHABET.indexOf(ACode[1+i]) = -1) then
          exit(false);
   end;

  Result := true;

end;

class function TOpenLocationCode.IsFullCode(const ACode: String): Boolean;
begin
  try
    Result := TOpenLocationCode.Create(ACode).IsFull;
  except
    on EArgumentException do exit(false);
  end;
end;

class function TOpenLocationCode.IsShortCode(const ACode: String): Boolean;
begin
  try
    Result := TOpenLocationCode.Create(ACode).isShort();
  except
   on EArgumentException do
     Exit(false);
  end;
end;

class function TOpenLocationCode.clipLatitude(ALatitude: Double): Double;
begin
  Result := Min(Max(ALatitude, -LATITUDE_MAX), LATITUDE_MAX);
end;


class function TOpenLocationCode.normalizeLongitude(ALongitude: Double): Double;
const
  CIRCLE_DEG = Int64(2 * LONGITUDE_MAX); // 360 degrees
begin
  if (ALongitude >= -LONGITUDE_MAX) and (ALongitude < LONGITUDE_MAX) then
      // longitude is within proper range, no normalization necessary
     exit(ALongitude);

  // % in Java uses truncated division with the remainder having the same sign as
    // the dividend. For any input longitude < -360, the result of longitude%CIRCLE_DEG
    // will still be negative but > -360, so we need to add 360 and apply % a second time.

  Result := (Trunc(ALongitude) mod CIRCLE_DEG + CIRCLE_DEG + LONGITUDE_MAX) mod CIRCLE_DEG - LONGITUDE_MAX;
end;

class function TOpenLocationCode.computeLatitudePrecision(ACodeLength: Integer): Double;
begin
  if (ACodeLength <= CODE_PRECISION_NORMAL) then
  begin
    Result := IntPower(ENCODING_BASE, ACodeLength div -2 + 2);
    exit;
  end;

  Result := IntPower(ENCODING_BASE, -3) / IntPower(GRID_ROWS, ACodeLength - PAIR_CODE_LENGTH);
end;

end.
