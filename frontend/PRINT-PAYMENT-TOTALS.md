# Impressão do resumo por forma de pagamento

Na tela Notas fiscais, os botões **Imprimir A4** e **Imprimir bobina 80 mm** ficam no painel Totais da consulta. Cada botão consulta novamente os totais com os filtros aplicados (período, ambiente, situação e busca), abre uma prévia e permite imprimir pelo navegador.

O relatório contém empresa/CNPJ, ambiente, período, situação, busca quando usada, data/hora de geração em Brasília, total geral sem canceladas e os valores de Dinheiro, PIX, Boleto, Cartão de crédito, Cartão de débito e Não informado. Não imprime relação de notas nem quantidades. Não altera dados ou documentos fiscais.

- **A4:** retrato, margens de 12 mm; pode usar Salvar como PDF.
- **80 mm:** papel de 80 mm na impressora, margens de 3 mm e área útil de 74 mm. O comprimento é calculado pelo conteúdo. Desativar cabeçalhos/rodapés do navegador e usar escala 100%; o driver deve oferecer o papel de bobina adequado.

Na impressão, menus, filtros editáveis, listagem e botões são ocultados. O relatório temporário é removido após fechar/cancelar a impressão. A forma de pagamento é controle interno e não comprova recebimento.

## Implantação manual pelo responsável

Pacote: `build/nfse-frontend-impressao.zip` (também copiado para `build/nfse-frontend-easypanel.zip`). Atualiza **somente nfse-web**. A API e a migração de pagamentos da versão anterior já devem estar instaladas; esta versão não contém nova migração ou executável do backend.

No EasyPanel, enviar o ZIP em **nfse-web > Fonte > Upload**, mantendo o builder Dockerfile e caminho `Dockerfile`. O Upload pode iniciar a implantação automaticamente conforme o comportamento do painel. Após concluir, usar Ctrl+F5 no site.

Esta entrega foi preparada sem enviar o pacote ao EasyPanel; a implantação fica com o usuário.

Validação: sintaxe Node; `node tests/print-totals-regression.mjs`; prévias A4/80 mm no navegador com dados fictícios. A impressão em equipamento físico depende do driver e foi deixada para o responsável.
