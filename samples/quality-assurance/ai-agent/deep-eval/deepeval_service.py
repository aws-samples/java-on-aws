from flask import Flask, request, jsonify
import logging
import json
import re

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)

@app.route('/health', methods=['GET'])
def health():
    return jsonify({"status": "healthy"})

@app.route('/evaluate', methods=['POST'])
def evaluate():
    try:
        # Use Flask's request.json with proper error handling
        if request.is_json:
            data = request.get_json()
        else:
            # Fallback: manually parse with sanitization
            raw_data = request.get_data(as_text=True)
            sanitized_data = re.sub(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]', '', raw_data)
            data = json.loads(sanitized_data)
        
        question = str(data.get('question', '')).strip()
        response = str(data.get('response', '')).strip()
        threshold = float(data.get('threshold', 0.3))
        
        # Sanitize text using proper string methods
        question = ''.join(char for char in question if ord(char) >= 32 or char in '\t\n\r')
        response = ''.join(char for char in response if ord(char) >= 32 or char in '\t\n\r')
        
        app.logger.info(f"Evaluating - Question: {question[:50]}..., Response: {response[:50]}...")
        
        if not question or not response:
            return jsonify({"error": "question and response are required"}), 400
        
        # Simple but effective relevancy scoring
        question_words = set(re.findall(r'\w+', question.lower()))
        response_words = set(re.findall(r'\w+', response.lower()))
        
        # Remove common stop words
        stop_words = {'the', 'a', 'an', 'and', 'or', 'but', 'in', 'on', 'at', 'to', 'for', 'of', 'with', 'by', 'is', 'are', 'was', 'were'}
        question_words -= stop_words
        response_words -= stop_words
        
        if not question_words:
            score = 0.5
            reason = "No meaningful words in question"
        else:
            # Calculate relevancy score
            exact_matches = len(question_words.intersection(response_words))
            partial_matches = sum(1 for qw in question_words 
                                if any(qw in rw or rw in qw for rw in response_words))
            
            # Scoring algorithm
            exact_score = exact_matches / len(question_words)
            partial_score = (partial_matches - exact_matches) / len(question_words) * 0.3
            length_bonus = min(len(response.split()) / 20, 0.2)
            
            score = min(exact_score + partial_score + length_bonus + 0.1, 1.0)
            reason = f"Exact matches: {exact_matches}/{len(question_words)}, Partial matches: {partial_matches - exact_matches}"
        
        success = score >= threshold
        
        result = {
            "score": round(score, 2),
            "success": success,
            "threshold": threshold,
            "reason": reason,
            "metric_type": "Enhanced Keyword Analysis",
            "model": "keyword-based-evaluator"
        }
        
        app.logger.info(f"Evaluation result: score={result['score']}, success={result['success']}")
        return jsonify(result)
        
    except Exception as e:
        app.logger.error(f"Evaluation error: {str(e)}")
        return jsonify({"error": f"Evaluation failed: {str(e)}"}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080, debug=True)