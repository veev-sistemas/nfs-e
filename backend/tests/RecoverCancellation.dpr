program RecoverCancellation;
{$APPTYPE CONSOLE}
// Administrative/offline helper: no HTTP client or fiscal request is invoked.
uses System.SysUtils, FireDAC.Comp.Client,
  ACBrDFeXsLibXml2 in '..\vendor\acbr-compat\ACBrDFeXsLibXml2.pas',
  PadraoNacional.GravarXml in '..\vendor\acbr-compat\PadraoNacional.GravarXml.pas',
  Nfse.Db, Nfse.Emission;
var Conn: TFDConnection; Q: TFDQuery; Guid: TGUID;
begin
  try
    if ParamCount<>2 then raise Exception.Create('Informe empresa e nota.');
    Guid:=StringToGUID('{'+ParamStr(1)+'}'); Guid:=StringToGUID('{'+ParamStr(2)+'}');
    Conn:=OpenDatabase;
    try
      ReconcileSavedCancellation(Conn,ParamStr(1),ParamStr(2));
      Q:=TFDQuery.Create(nil);
      try
        Q.Connection:=Conn;
        Q.SQL.Text:='select i.status,a.status as cancellation_status from invoices i left join cancellation_attempts a '+
          'on a.invoice_id=i.id and a.company_id=i.company_id where i.id=cast(:invoice as uuid) '+
          'and i.company_id=cast(:company as uuid) order by a.created_at desc limit 1';
        Q.ParamByName('invoice').AsWideString:=ParamStr(2); Q.ParamByName('company').AsWideString:=ParamStr(1); Q.Open;
        if Q.IsEmpty then raise Exception.Create('Nota nao encontrada.');
        Writeln('invoice_status='+Q.Fields[0].AsString+' cancellation_status='+Q.Fields[1].AsString);
        if Q.Fields[0].AsString<>'cancelled' then Halt(2);
      finally Q.Free; end;
    finally Conn.Free; end;
  except on E:Exception do begin Writeln('Nao foi possivel confirmar o evento salvo.'); Halt(1); end; end;
end.
