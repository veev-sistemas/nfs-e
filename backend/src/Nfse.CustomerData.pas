unit Nfse.CustomerData;
interface
uses System.SysUtils, System.JSON;
function CustomerDetails(Body:TJSONObject):TJSONObject;
function CustomerText(Body:TJSONObject; const Key:string):string;
implementation
uses System.RegularExpressions;
function CustomerText(Body:TJSONObject; const Key:string):string;
var V:TJSONValue;
begin
 V:=Body.GetValue(Key);
 if (V=nil) or (V is TJSONNull) then Exit('');
 if not (V is TJSONString) then raise EArgumentException.Create(Key+' deve ser texto.');
 Result:=Trim(V.Value);
end;
function CustomerDetails(Body:TJSONObject):TJSONObject;
const Keys:array[0..9] of string=('phone','email','postal_code','municipality_code','municipality_name','state_code','district','street','house_number','complement');
 Limits:array[0..9] of Integer=(20,80,8,7,100,2,60,255,60,156);
 RequiredAddress:array[0..5] of string=('postal_code','municipality_code','state_code','district','street','house_number');
 States='|RO11|AC12|AM13|RR14|PA15|AP16|TO17|MA21|PI22|CE23|RN24|PB25|PE26|AL27|SE28|BA29|MG31|ES32|RJ33|SP35|PR41|SC42|RS43|MS50|MT51|GO52|DF53|';
var I:Integer; Value,UF,Code:string; HasAddress:Boolean;
begin
 Result:=TJSONObject.Create;
 try
  HasAddress:=False;
  for I:=0 to High(Keys) do begin
   Value:=CustomerText(Body,Keys[I]);
   if (Keys[I]='phone') or (Keys[I]='postal_code') then begin
    if (Value<>'') and not TRegEx.IsMatch(Value,'^[0-9 ()+.-]+$') then raise EArgumentException.Create(Keys[I]+' invalido.');
    Value:=TRegEx.Replace(Value,'[^0-9]','');
   end;
   if Keys[I]='state_code' then Value:=UpperCase(Value);
   if Length(Value)>Limits[I] then raise EArgumentException.Create(Keys[I]+' muito longo.');
   if Value<>'' then begin
    if (Keys[I]='phone') and not TRegEx.IsMatch(Value,'^[0-9]{6,20}$') then raise EArgumentException.Create('Telefone deve ter de 6 a 20 digitos.');
    if (Keys[I]='email') and not TRegEx.IsMatch(Value,'^[^\s@]+@[^\s@]+\.[^\s@]+$') then raise EArgumentException.Create('E-mail invalido.');
    if (Keys[I]='postal_code') and not TRegEx.IsMatch(Value,'^[0-9]{8}$') then raise EArgumentException.Create('CEP deve conter oito digitos.');
    if (Keys[I]='municipality_code') and not TRegEx.IsMatch(Value,'^[0-9]{7}$') then raise EArgumentException.Create('Codigo IBGE deve conter sete digitos.');
    Result.AddPair(Keys[I],Value);
    if I>=2 then HasAddress:=True;
   end;
  end;
  if HasAddress then begin
   for I:=0 to High(RequiredAddress) do
    if CustomerText(Result,RequiredAddress[I])='' then raise EArgumentException.Create('Endereco opcional: para envia-lo na nota, complete CEP, municipio IBGE, UF, bairro, logradouro e numero; ou deixe todo o endereco vazio.');
   UF:=CustomerText(Result,'state_code');Code:=CustomerText(Result,'municipality_code');
   if Pos('|'+UF+Copy(Code,1,2)+'|',States)=0 then raise EArgumentException.Create('Municipio IBGE nao corresponde a UF.');
  end;
 except Result.Free;raise;end;
end;
end.
