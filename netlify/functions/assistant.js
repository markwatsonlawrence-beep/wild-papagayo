// Wild Papagayo - AI Travel Assistant (Netlify Function)
// Answers visitor questions grounded ONLY in assistant-knowledge.json
// (compiled by assistant-knowledge-generator.ps1 from the real
// knowledge graph). Runs server-side so ANTHROPIC_API_KEY never
// reaches the browser. Redeploy after regenerating the knowledge file.

const Anthropic = require('@anthropic-ai/sdk');
const knowledge = require('./assistant-knowledge.json');

const client = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });

const SYSTEM_PROMPT = `You are Bubu, the Wild Papagayo Travel Assistant, embedded on wildpapagayo.com. If asked your name, say you're Bubu.

Wild Papagayo is a private tour and transportation company in Guanacaste and Arenal, Costa Rica (private day tours, airport transfers, private drivers -- not group bus tours). WhatsApp: ${knowledge.company.whatsapp}

Answer ONLY using the knowledge below. If the answer isn't in this data, say you don't have that specific detail and suggest the visitor ask via WhatsApp -- never invent hotel names, tour details, prices, or availability.

Keep replies short (2-5 sentences), warm, and specific -- name the actual hotel/tour/destination/article involved when relevant, and link to it using the "url" field (as a relative path, e.g. "/tours/slug.html"). When a reply would naturally lead to a booking or a specific question the team should handle personally, suggest continuing on WhatsApp.

KNOWLEDGE GRAPH:
${JSON.stringify(knowledge, null, 0)}`;

exports.handler = async (event) => {
  const headers = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Content-Type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
  };

  if (event.httpMethod === 'OPTIONS') {
    return { statusCode: 204, headers, body: '' };
  }
  if (event.httpMethod !== 'POST') {
    return { statusCode: 405, headers, body: JSON.stringify({ error: 'Method not allowed' }) };
  }

  let payload;
  try {
    payload = JSON.parse(event.body || '{}');
  } catch (e) {
    return { statusCode: 400, headers, body: JSON.stringify({ error: 'Invalid JSON body' }) };
  }

  const message = String(payload.message || '').trim();
  const history = Array.isArray(payload.history) ? payload.history.slice(-8) : [];
  if (!message) {
    return { statusCode: 400, headers, body: JSON.stringify({ error: 'message is required' }) };
  }
  if (message.length > 800) {
    return { statusCode: 400, headers, body: JSON.stringify({ error: 'message is too long' }) };
  }

  try {
    const response = await client.messages.create({
      model: 'claude-opus-4-8',
      max_tokens: 500,
      system: [
        { type: 'text', text: SYSTEM_PROMPT, cache_control: { type: 'ephemeral' } },
      ],
      messages: [
        ...history
          .filter(m => m && (m.role === 'user' || m.role === 'assistant') && typeof m.content === 'string')
          .map(m => ({ role: m.role, content: m.content })),
        { role: 'user', content: message },
      ],
    });

    const textBlock = response.content.find(b => b.type === 'text');
    const reply = textBlock ? textBlock.text : "Sorry, I couldn't come up with an answer -- please try WhatsApp instead.";

    return { statusCode: 200, headers, body: JSON.stringify({ reply }) };
  } catch (err) {
    console.error('Assistant error:', err);
    return { statusCode: 500, headers, body: JSON.stringify({ error: 'The assistant is temporarily unavailable. Please try WhatsApp instead.' }) };
  }
};
