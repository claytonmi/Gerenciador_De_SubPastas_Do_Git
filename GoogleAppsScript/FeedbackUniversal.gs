/**
 * Endpoint universal de feedback para os aplicativos do proprietário.
 * Publique como Web App executando como o proprietário e permita acesso
 * aos clientes necessários. O cliente não precisa de senha SMTP/Google.
 *
 * Payload JSON recomendado:
 * { system, name, email, subject, message, website }
 * `system` identifica o aplicativo. `website` deve ficar vazio (honeypot).
 * Também aceita `app`, `application` e os nomes legados em português.
 */
const FEEDBACK_DESTINATION = 'clayton-mi@live.com';
const MAX_FEEDBACK_PER_DAY = 30;
const PER_SENDER_INTERVAL_SECONDS = 60;
const DEFAULT_SYSTEM_NAME = 'Sistema não identificado';

function doPost(e) {
  try {
    const data = JSON.parse(e && e.postData ? e.postData.contents : '{}');

    // Honeypot simples para reduzir envios automatizados.
    if (String(data.website || '').trim() !== '') {
      return jsonResponse_({ ok: false, message: 'Feedback inválido.' });
    }

    const feedback = validateFeedback_(data);
    const quota = reserveQuota_(feedback.email);
    if (!quota.ok) {
      return jsonResponse_({ ok: false, message: quota.message });
    }

    MailApp.sendEmail({
      to: FEEDBACK_DESTINATION,
      subject: '[' + feedback.system + '] ' + feedback.subject,
      body: [
        'Novo feedback recebido pelo sistema: ' + feedback.system,
        '',
        'Nome: ' + feedback.name,
        'E-mail de contato: ' + feedback.email,
        'Sistema: ' + feedback.system,
        '',
        'Assunto: ' + feedback.subject,
        '',
        'Mensagem:',
        feedback.message
      ].join('\n'),
      replyTo: feedback.email,
      name: feedback.system + ' - Feedback'
    });

    return jsonResponse_({ ok: true, message: 'Feedback enviado com sucesso.' });
  } catch (err) {
    // O detalhe fica no log de Execuções; não expomos erros internos ao cliente.
    console.error('Falha ao processar feedback: ' + String(err));
    return jsonResponse_({ ok: false, message: 'Não foi possível enviar o feedback.' });
  }
}

function validateFeedback_(data) {
  const name = readFirst_(data, ['name', 'nome']);
  const email = readFirst_(data, ['email']);
  const subject = readFirst_(data, ['subject', 'assunto']);
  const message = readFirst_(data, ['message', 'mensagem']);
  const system = readFirst_(data, ['system', 'app', 'application', 'sistema', 'aplicativo']) ||
    DEFAULT_SYSTEM_NAME;

  if (!name || name.length > 100) throw new Error('Nome inválido.');
  if (email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    throw new Error('E-mail inválido.');
  }
  if (!subject || subject.length > 150 || /[\r\n]/.test(subject)) {
    throw new Error('Assunto inválido.');
  }
  if (!message || message.length > 500) throw new Error('Mensagem inválida.');
  if (system.length > 100 || /[\r\n]/.test(system)) throw new Error('Sistema inválido.');

  return { system: system, name: name, email: email, subject: subject, message: message };
}

function readFirst_(data, keys) {
  for (let i = 0; i < keys.length; i++) {
    const value = String(data[keys[i]] || '').trim();
    if (value) return value;
  }
  return '';
}

function reserveQuota_(email) {
  const lock = LockService.getScriptLock();
  lock.waitLock(5000);
  try {
    const day = Utilities.formatDate(new Date(), 'Etc/UTC', 'yyyy-MM-dd');
    const properties = PropertiesService.getScriptProperties();
    const storedDay = properties.getProperty('feedback_day');
    let count = Number(properties.getProperty('feedback_count') || '0');

    if (storedDay !== day) {
      count = 0;
      properties.setProperty('feedback_day', day);
      properties.setProperty('feedback_count', '0');
    }
    if (count >= MAX_FEEDBACK_PER_DAY) {
      return { ok: false, message: 'Limite diário de feedbacks atingido. Tente novamente amanhã.' };
    }

    const senderKey = 'feedback_sender_' + sha256Hex_(email.toLowerCase());
    const cache = CacheService.getScriptCache();
    if (cache.get(senderKey)) {
      return { ok: false, message: 'Aguarde um minuto antes de enviar outro feedback.' };
    }

    properties.setProperty('feedback_count', String(count + 1));
    cache.put(senderKey, '1', PER_SENDER_INTERVAL_SECONDS);
    return { ok: true };
  } finally {
    lock.releaseLock();
  }
}

function sha256Hex_(value) {
  return Utilities.computeDigest(Utilities.DigestAlgorithm.SHA_256, value)
    .map(function (byte) {
      return ('0' + ((byte + 256) % 256).toString(16)).slice(-2);
    })
    .join('');
}

function jsonResponse_(payload) {
  return ContentService.createTextOutput(JSON.stringify(payload))
    .setMimeType(ContentService.MimeType.JSON);
}
