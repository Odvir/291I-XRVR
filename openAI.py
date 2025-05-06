from openai import OpenAI
from dotenv import load_dotenv
import os

# Load the .env file
load_dotenv()
openai_api_key = os.getenv("API_KEY")
client = OpenAI(api_key=openai_api_key)

response = client.responses.create(
    model="gpt-4o-mini",
    input="Write a one-sentence explanation on why pride and prejudice is great"
)

print(response.output_text)