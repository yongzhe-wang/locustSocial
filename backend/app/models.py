from pydantic import BaseModel, Field
from typing import Optional, List

from math import sqrt

class PostCreate(BaseModel):
    title: str = Field(min_length=1)
    body: Optional[str] = ""

class PostOut(BaseModel):
    id: int
    title: str
    body: str | None = None

class SearchOut(BaseModel):
    id: int
    title: str
    body: str | None = None

class SearchRequest(BaseModel):
    q: str
    limit: int = 20

class ErrorOut(BaseModel):
    detail: str

class BatchCreateOut(BaseModel):
    inserted_ids: List[int]


from typing import Optional
from pydantic import BaseModel

# ... existing models ...

class FirebasePostIn(BaseModel):
    firebase_id: str          # Firestore doc id
    title: Optional[str] = "" # sometimes you may only send body
    body: Optional[str] = ""
    image_b64: Optional[str] = None  # we'll let the cloud function send the image
    user_id: Optional[str] = None    # optional, for auditing


# add near the other models
class UserEventIn(BaseModel):
    uid: str
    etype: str  # 'view' | 'like' | 'comment' | 'share'
    firebase_post_id: str | None = None
    post_id: int | None = None
    weight: float | None = None  # optional override

class AdaptContentRequest(BaseModel):
    text: str
    title: str | None = None
    style: str = "engaging"
    uid: str | None = None

class AdaptContentResponse(BaseModel):
    adapted_text: str
    adapted_title: str | None = None
    facts: List[str]
    modifications: List[str]
