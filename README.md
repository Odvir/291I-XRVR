# Beyond the Cover: AR Insights to Spark Reading with VLMs

Research prototype combining object detection with a visual-language model (VLM) to detect, crop, and describe book covers.

This repo documents experiments and a small iPhone MVP that demonstrate an end-to-end flow:
- detect objects on-device using TensorFlow Lite (TFLite) models,
- extract crops for detected items (for example, book covers),
- send crops or detection metadata to a VLM/backend helper to generate human-friendly captions or descriptions.

The codebase is intended as a research prototype and demo: scripts in Python provide quick experiments and helpers, while `MVP_iphone/` contains a minimal Swift app showing on-device inference with the included TFLite models.

**Project report**
- [Project Report (PDF)](https://drive.google.com/file/d/1cS4Hh0JnYkqH5SDeQ-S3h-iVyowGddyG/view?usp=sharing)

**What this repo contains**
- `object_detection_VLM.py`: Experiment script that runs object detection, crops detected regions, and formats prompts for a VLM backend.
- `screenshot_vlm.py`: Utility to capture screenshots, run detection on the capture, and query the VLM for quick demos.
- `VLM/openAI.py`: Small helper module for calling an OpenAI-style API or another VLM endpoint (configure your API key/settings here).
- `object-detection/`: Example scripts and the included TFLite models used during experiments (`efficientdet_lite0.tflite`, `efficientdet_lite2.tflite`).
- `MVP_iphone/`: iOS example app demonstrating on-device inference and simple UI integration.

**Models included**
- `efficientdet_lite0.tflite`, `efficientdet_lite2.tflite` — lightweight object detection models used by the experiments and the iPhone MVP.

**Quick start**
1. Install dependencies used by the Python scripts
2. Edit `VLM/openAI.py` to add your API key or configure the VLM backend.
3. Run a demo from the project root:

```bash
python3 object_detection_VLM.py
# or
python3 screenshot_vlm.py
```
---

## Example Result

### Book: 
Pride and Prejudice

### AI Image Detection Description:
The image features a beautifully designed edition of "Pride and Prejudice" by Jane Austen, resting on a wooden surface. The book cover has elegant typography, outlining the title in a graceful script. The background is adorned with handwritten notes, adding a vintage touch. A decorative blue spine, embellished with a peacock feather motif, enhances its appeal. Nearby, a pen and an ornate silver tray suggest a setting for thoughtful reading or letter writing.

### AI Generated Poem: Whispers of Pride and Prejudice

In a world of letters, ink, and sighs,
Where hearts entwine beneath the skies,
A tale unfolds with grace and wit,
Of love and mischief, where two souls fit.

With pride and prejudice, they dance and weave,
In manners and mores, their truths deceive;
Yet through the pages, passion’s light,
Ignites the darkness, sets wrongs to right.

Each fold and letter, secrets untold,
In whispers of longing, their stories unfold;
Elizabeth’s spirit, and Darcy’s proud heart,
Craft a romance that won’t soon depart.

So gather, dear reader, let’s turn each page,
Embrace the wisdom of Austen’s age;
For in her words, we find a mirror,
Reflecting our hearts, growing ever nearer.