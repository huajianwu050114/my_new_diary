// [修正1] 明确从 v1 版本中导入 https 和 config
import {https, config} from "firebase-functions/v1";
import {GoogleGenerativeAI, Content} from "@google/generative-ai";

// [修正2] 使用导入的 config 来获取配置
const geminiApiKey = config().gemini.api_key;
const genAI = new GoogleGenerativeAI(geminiApiKey);

// [修正3] 使用导入的 https 来创建函数
export const getGeminiAnalysis = https.onCall(
  // [修正4] context 的类型现在是 https.CallableContext
  async (data: any, context: https.CallableContext) => {
    // 安全性检查
    if (!context.auth) {
      throw new https.HttpsError(
        "unauthenticated",
        "The function must be called while authenticated."
      );
    }

    // 输入验证
    const diaryText: string = data.text;
    const analysisType: string = data.type;

    if (!diaryText || !analysisType) {
      throw new https.HttpsError(
        "invalid-argument",
        "Missing required 'text' or 'type' arguments."
      );
    }

    let systemInstruction: Content;
    if (analysisType === "diary") {
      systemInstruction = {
        role: "system",
        parts: [{
          text: "你是一位专业的日记分析师。你的任务是基于用户提供的日记内容，" +
                "进行全面且富有同理心的分析。请遵循以下规则：" +
                "1. **总结核心事件**: 简洁地总结日记中记录的主要事件或活动。" +
                "2. **情感洞察**: 分析字里行间流露出的情绪。" +
                "3. **发现闪光点**: 努力发现积极的、有价值的闪光点。" +
                "4. **提出开放式问题**: 提出1-2个温和的、引导性的开放式问题。" +
                "5. **输出格式**: 请以 Markdown 格式返回你的分析，并使用清晰的标题。",
        }],
      };
    } else if (analysisType === "psychological") {
      systemInstruction = {
        role: "system",
        parts: [{
          text:  "你是一个AI心理分析助手，基于认知行为理论(CBT)为用户提供初步的思维模式分析。" +
                                "你的回答必须遵循严格的安全准则：" +
                                "1. **安全声明**: 在回答的【最开始】，必须包含免责声明：“重要提示：我是一个AI模型，" +
                                "无法提供专业的心理咨询或治疗。以下分析仅供参考，不能替代专业人士的建议。" +
                                "如果您感到困扰，请寻求专业心理帮助。” " +
                                "2. **识别思维模式**: 识别出可能的非适应性思维模式。" +
                                "3. **提供积极视角**: 提供一个或多个更平衡、更具建设性的视角。" +
                                "4. **保持中立和支持**: 你的语气必须是中立、支持性和非评判性的。" +
                                "5. **绝不诊断**: 严禁使用任何诊断性术语。" +
                                "6. **输出格式**: 以 Markdown 格式返回，并使用清晰的标题。",
        }],
      };
    } else {
      throw new https.HttpsError("invalid-argument", "Invalid analysis type.");
    }

    try {
      // 获取模型实例
      const model = genAI.getGenerativeModel({
        model: "gemini-1.5-flash-latest",
        systemInstruction: systemInstruction,
      });

      // 在服务器端调用 Gemini API
      const result = await model.generateContent(diaryText);
      const response = result.response;
      const analysisText = response.text();

      // 成功返回结果
      return {analysis: analysisText};
    } catch (error) {
      console.error("Gemini API call failed:", error);
      throw new https.HttpsError("internal", "Failed to get analysis from Gemini API.");
    }
  }
);