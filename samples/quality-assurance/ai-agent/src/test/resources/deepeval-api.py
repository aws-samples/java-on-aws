#!/usr/bin/env python3
"""
DeepEval REST API Service
Provides HTTP endpoints for AI evaluation using DeepEval framework
"""

from flask import Flask, request, jsonify
from deepeval.metrics import AnswerRelevancyMetric, FaithfulnessMetric
from deepeval.test_case import LLMTestCase
from deepeval.models import DeepEvalBaseLLM
import requests
import json
import os

app = Flask(__name__)

class OllamaModel(DeepEvalBaseLLM):
    def __init__(self, base_url="http://ollama:11434", model="llama3.2:3b"):
        self.base_url = base_url
        self.model = model
        self._ensure_model_available()
    
    def _ensure_model_available(self):
        """Pull model if not available"""
        try:
            requests.post(
                f"{self.base_url}/api/pull",
                json={"name": self.model},
                timeout=300
            )
        except Exception as e:
            print(f"Warning: Could not pull model {self.model}: {e}")

    def load_model(self):
        return self

    def generate(self, prompt):
        try:
            response = requests.post(
                f"{self.base_url}/api/generate",
                json={
                    "model": self.model, 
                    "prompt": prompt, 
                    "stream": False,
                    "options": {
                        "temperature": 0.1,
                        "top_p": 0.9,
                        "num_predict": 512
                    }
                },
                timeout=120
            )
            if response.status_code != 200:
                return f"HTTP Error {response.status_code}: {response.text}"
            
            result = response.json().get("response", "Unable to evaluate")
            print(f"LLM Prompt: {prompt[:100]}...")
            print(f"LLM Response: {result}")
            return result
        except Exception as e:
            error_msg = f"Evaluation failed: {str(e)}"
            print(error_msg)
            return error_msg
    
    async def a_generate(self, prompt):
        """Async version of generate method"""
        return self.generate(prompt)

    def get_model_name(self):
        return f"ollama-{self.model}"

@app.route('/health', methods=['GET'])
def health():
    return jsonify({"status": "healthy", "service": "deepeval-api"})

@app.route('/evaluate/relevancy', methods=['POST'])
def evaluate_relevancy():
    try:
        data = request.json
        question = data.get('input', '')
        response = data.get('output', '')
        threshold = data.get('threshold', 0.5)
        
        # Create DeepEval test case
        test_case = LLMTestCase(input=question, actual_output=response)
        
        # Use Ollama model for evaluation
        ollama_model = OllamaModel()
        metric = AnswerRelevancyMetric(threshold=threshold, model=ollama_model)
        
        # Perform DeepEval evaluation
        metric.measure(test_case)
        
        result = {
            'score': float(metric.score) if metric.score else 0.0,
            'success': metric.success,
            'reason': str(metric.reason),
            'metric': 'answer_relevancy'
        }
        
        return jsonify(result)
    
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/evaluate/faithfulness', methods=['POST'])
def evaluate_faithfulness():
    try:
        data = request.json
        question = data.get('input', '')
        response = data.get('output', '')
        context = data.get('context', [])
        threshold = data.get('threshold', 0.5)
        
        # Create DeepEval test case
        test_case = LLMTestCase(
            input=question, 
            actual_output=response, 
            retrieval_context=context
        )
        
        # Use Ollama model for evaluation
        ollama_model = OllamaModel()
        metric = FaithfulnessMetric(threshold=threshold, model=ollama_model)
        
        # Perform DeepEval evaluation
        metric.measure(test_case)
        
        result = {
            'score': float(metric.score) if metric.score else 0.0,
            'success': metric.success,
            'reason': str(metric.reason),
            'metric': 'faithfulness'
        }
        
        return jsonify(result)
    
    except Exception as e:
        return jsonify({'error': str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080, debug=True)