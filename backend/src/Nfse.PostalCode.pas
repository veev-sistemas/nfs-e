unit Nfse.PostalCode;
interface
uses System.SysUtils, System.JSON;
function LookupPostalCode(const CEP:string):string;
implementation
uses System.Classes, Nfse.CustomerData;
{$IFDEF LINUX}
function PostalPopen(Command,Mode:MarshaledAString):Pointer;cdecl;external 'libc.so.6' name 'popen';
function PostalRead(Buffer:Pointer;Size,Count:NativeUInt;Stream:Pointer):NativeUInt;cdecl;external 'libc.so.6' name 'fread';
function PostalClose(Stream:Pointer):Integer;cdecl;external 'libc.so.6' name 'pclose';
{$ENDIF}
function LookupPostalCode(const CEP:string):string;
var Data:TJSONObject;Value:TJSONValue;Ch:Char;
{$IFDEF LINUX}
 Pipe:Pointer;Command:UTF8String;Buffer:array[0..1023] of Byte;Count:NativeUInt;Output:TMemoryStream;Bytes:TBytes;Status:Integer;
{$ENDIF}
begin
 if Length(CEP)<>8 then raise EArgumentException.Create('CEP deve conter oito digitos.');
 for Ch in CEP do if not CharInSet(Ch,['0'..'9']) then raise EArgumentException.Create('CEP invalido.');
 {$IFDEF LINUX}
 // Fixed HTTPS destination and digits-only CEP: never execute user-provided shell syntax.
 Command:=UTF8String('/usr/bin/curl --fail --silent --connect-timeout 5 --max-time 8 --proto =https https://viacep.com.br/ws/'+CEP+'/json/');
 Pipe:=PostalPopen(MarshaledAString(Command),'r');
 if Pipe=nil then raise Exception.Create('Consulta de CEP indisponivel.');
 Output:=TMemoryStream.Create;
 try
  try
   repeat
    Count:=PostalRead(@Buffer[0],1,SizeOf(Buffer),Pipe);
    if Count>0 then Output.WriteBuffer(Buffer[0],Count);
    if Output.Size>65536 then raise Exception.Create('Resposta de CEP muito longa.');
   until Count=0;
  finally Status:=PostalClose(Pipe);end;
  if Status<>0 then raise Exception.Create('Consulta de CEP indisponivel.');
  SetLength(Bytes,Output.Size);Output.Position:=0;
  if Length(Bytes)>0 then Output.ReadBuffer(Bytes[0],Length(Bytes));
  Value:=TJSONObject.ParseJSONValue(TEncoding.UTF8.GetString(Bytes));
 finally Output.Free;end;
 {$ELSE}
 raise Exception.Create('Consulta de CEP disponivel no servidor Linux.');
 Value:=nil;
 {$ENDIF}
 if not (Value is TJSONObject) then begin Value.Free;raise Exception.Create('Resposta de CEP invalida.');end;
 Data:=TJSONObject(Value);
 try
  if Data.GetValue('erro')<>nil then raise EArgumentException.Create('CEP nao encontrado. Confira ou preencha manualmente.');
  with TJSONObject.Create do
  try
   AddPair('postal_code',CEP);AddPair('street',CustomerText(Data,'logradouro'));
   AddPair('district',CustomerText(Data,'bairro'));AddPair('municipality_name',CustomerText(Data,'localidade'));
   AddPair('state_code',CustomerText(Data,'uf'));AddPair('municipality_code',CustomerText(Data,'ibge'));
   Result:=ToJSON;
  finally Free;end;
 finally Data.Free;end;
end;
end.
