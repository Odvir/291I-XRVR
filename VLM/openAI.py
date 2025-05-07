from openai import OpenAI
from dotenv import load_dotenv
import os
import base64

# Load the .env file
load_dotenv()
openai_api_key = os.getenv("API_KEY")
client = OpenAI(api_key=openai_api_key)

# Read the image and encode it as base64
with open("snapshot_0.png", "rb") as image_file:
    base64_image = base64.b64encode(image_file.read()).decode('utf-8')

# Call GPT-4o (or GPT-4 Vision) with the image
response = client.chat.completions.create(
    model="gpt-4o-mini",  # or "gpt-4-vision-preview"
    messages=[
        {
            "role": "user",
            "content": [
                {"type": "text", "text": "Describe this image. and write a poem about it"},
                {"type": "image_url", "image_url": {"url": f"data:image/png;base64,{base64_image}"}}

            ]
        }
    ],
    max_tokens=300
)

# Print the description
print(response.choices[0].message.content)