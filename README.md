# Gerenciador de Pastas do Git

### 🧩 Sobre o Sistema
O Gerenciador de Pastas do Git é uma ferramenta desenvolvida para facilitar a troca de branches em múltiplos repositórios Git localizados dentro de uma pasta principal.

### 🚀 Funcionalidade principal
O sistema permite que o usuário:

- Identifique automaticamente subpastas com repositórios Git dentro da pasta onde o sistema foi aberto.

- Liste essas subpastas no combo Subpastas Git.

- Exiba todas as branches disponíveis de todos os repositórios Git detectados no combo Branches.

  - Ao selecionar uma subpasta específica, o combo de branches será atualizado para mostrar apenas as branches dessa subpasta.

- Permita que o usuário selecione uma ou todas as pastas e escolha uma branch para trocar.

- Execute a troca de branch de forma automatizada.

- Exiba os resultados no painel de log, com indicações de sucesso ou erro durante o processo.

### 🛠 Instalação
O sistema é distribuído em formato executável e está disponível nas versões 32 bits e 64 bits.

[![Baixar instalador do Gerenciador de Pastas do Git](https://img.shields.io/badge/Baixar-Instalador%20(32%20e%2064%20bits)-2ea44f?style=for-the-badge)](https://github.com/claytonmi/Gerenciador_De_SubPastas_Do_Git/raw/refs/heads/main/Download/GerenciadorDePastasDoGit-Setup.exe)

O botão baixa diretamente o instalador disponível na pasta `Download` deste repositório. Em Windows 64 bits, o instalador permite escolher a versão de 32 ou 64 bits; em Windows 32 bits, instala a versão de 32 bits.

### ⚙️ Como instalar:
1.Baixe o instalador apropriado para sua arquitetura (32 ou 64 bits).

2.Execute o instalador.

3.Conclua o processo de instalação.

4.Após instalado, clique com o botão direito sobre a pasta principal que contém os repositórios Git e abra o sistema.


### 🧾 Logs
- O sistema armazena logs diários dentro da pasta raiz do aplicativo.

- O painel principal exibe o log da operação atual.

- Você pode:

  - Copiar o log atual diretamente do sistema.

  - Abrir o log completo, que inclui todos os comandos utilizados e suas respectivas saídas.

### 📋 Menu do Sistema
O sistema conta com um menu superior com as seguintes opções:

- Configuração:

  - Defina o caminho do executável do Git.

  - Configure o caminho do arquivo .ppk (para conexões SSH via PuTTY/Pageant).

- Guia de Uso:

  - Acesso rápido às instruções de uso da ferramenta.

- Enviar Feedback:

  - Permite ao usuário enviar sugestões ou reportar problemas diretamente ao desenvolvedor.

### 📦 Requisitos
- Windows (32 ou 64 bits).
- Git instalado e acessível via linha de comando (configurável no painel de configurações).
- Repositórios Git válidos nas subpastas da pasta principal.
  

### 💬 Feedback
Sua opinião é importante! Utilize a opção Enviar Feedback no menu do sistema para contribuir com melhorias.

O endpoint reutilizável do Google Apps Script está em `GoogleAppsScript/FeedbackUniversal.gs`.
Ele recebe o nome, e-mail, assunto, mensagem e identificador do sistema (`system`), e encaminha
os feedbacks para o endereço configurado em `FEEDBACK_DESTINATION`. Cada aplicativo pode usar
a mesma implantação e informar seu próprio identificador para aparecer no assunto e no corpo
do e-mail. O endpoint também aceita os nomes legados em português (`nome`, `assunto`, `mensagem`)
e usa “Sistema não identificado” quando o campo `system` não é enviado.

Para aplicar a alteração, atualize o código no projeto Apps Script vinculado à URL configurada
no Delphi e publique uma nova versão da implantação Web App. Ela deve executar como o proprietário,
que precisa autorizar o envio pelo `MailApp`. Os outros aplicativos devem enviar JSON com os campos
`system`, `name`, `email`, `subject` e `message`; o campo opcional `website` deve permanecer vazio.

### Integração com o menu de contexto do Windows

O projeto inclui o script InstalarMenuContextoGit.ps1 para registrar a opção no menu de pastas do usuário atual. Depois de compilar o programa, execute no PowerShell:

    .\InstalarMenuContextoGit.ps1 -ExecutablePath "C:\caminho\para\GerenciadorDePastas.exe"

Para remover a opção:

    .\InstalarMenuContextoGit.ps1 -Uninstall

Ao clicar com o botão direito em uma pasta e abrir o Gerenciador, essa pasta será a raiz da busca. O programa considera somente os repositórios Git que estão diretamente dentro dela, em ordem alfabética; não desce para subpastas. No Windows 11, a opção pode aparecer em Mostrar mais opções.

### Operacao Git

A lista mostra primeiro as branches locais e depois as referencias remotas, em ordem alfabetica dentro de cada grupo. Sao exibidas referencias ja existentes no cache local do Git; o programa nao executa fetch automatico. Ao selecionar uma branch local, o programa faz checkout e `pull --ff-only` pelo upstream configurado. Ao selecionar uma referencia remota, se ja existir uma branch local correspondente, faz checkout nela e executa `pull --ff-only <remote> <branch>` para atualizar exatamente pela referencia selecionada. Se a branch local nao existir, cria uma branch de acompanhamento (`checkout --track -b`) e executa `pull --ff-only`. O remote pode ter qualquer nome, como `origin` ou `upstream`. O fluxo e sequencial e ignora repositorios sem a referencia escolhida ou com alteracoes locais. Nao executa commit nem push.
