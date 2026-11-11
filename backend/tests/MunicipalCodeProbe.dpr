program MunicipalCodeProbe;
{$APPTYPE CONSOLE}
uses System.SysUtils, System.JSON;
type EEmissionError=class(Exception);
function MunicipalServiceCode(Settings: TJSONObject): string;
var V: TJSONValue;
begin
  V:=Settings.GetValue('municipal_service_code');
  if (V=nil) or (V is TJSONNull) then Exit('');
  if not (V is TJSONString) then
    raise EEmissionError.Create('Codigo municipal deve ser texto.');
  Result:=Trim(V.Value);
  if Result<>'' then
  begin
    if Length(Result)<>3 then raise EEmissionError.Create('Codigo municipal deve conter tres digitos.');
    if not CharInSet(Result[1],['0'..'9']) or not CharInSet(Result[2],['0'..'9']) or not CharInSet(Result[3],['0'..'9']) then
      raise EEmissionError.Create('Codigo municipal deve conter somente digitos.');
  end;
end;


procedure Check(const Json,Expected: string);
var O:TJSONObject;
begin
 O:=TJSONObject.ParseJSONValue(Json) as TJSONObject;
 try if MunicipalServiceCode(O)<>Expected then raise Exception.Create('Unexpected code'); finally O.Free;end;
end;
var O:TJSONObject; Rejected:Boolean;
begin
 Check('{}',''); Check('{"municipal_service_code":""}','');
 Check('{"municipal_service_code":null}','');
 Check('{"municipal_service_code":"002"}','002');
 O:=TJSONObject.ParseJSONValue('{"municipal_service_code":"abc"}') as TJSONObject;
 try
  Rejected:=False;
  try MunicipalServiceCode(O);except on E:EEmissionError do Rejected:=True;end;
  if not Rejected then Halt(1);
 finally O.Free;end;
 Writeln('OK: empty, absent, null, valid and invalid municipal code in emission accessor.');
end.
