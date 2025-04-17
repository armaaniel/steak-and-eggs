import React, { useState } from "react";

const BuySell = () => {
  const [currentState, setCurrentState] = useState({ action: "buy", step: 1 });

  const nextStep = () =>
    setCurrentState({ ...currentState, step: currentState.step + 1 });
  const prevStep = () =>
    setCurrentState({ ...currentState, step: currentState.step - 1 });
  const buyState = () => setCurrentState({ action: "buy", step: 1 });
  const sellState = () => setCurrentState({ action: "sell", step: 1 });

  return (
    <>
      {currentState.action === "buy" && currentState.step === 1 && (
        <div className='bs-parent-container'>
		  
          <div className='bs-button-container'>
            <button onClick={buyState} className='buy-sell-button'>Buy</button>
            <button onClick={sellState} className='buy-sell-button'>Sell</button>
          </div>
		  
		  <div className='bs-containers'>
		  	<div className='bs-width-wrapper'>
		  	<p>Order Type</p>
		  	</div>
		  	<div>
		  	<p>Market Buy</p>
		  	</div>
		  </div>
		  
		  <div className='bs-containers'>
		  	<div className='bs-shares-wrapper'>
          	<label>Shares</label>
		  	</div>
          	<form>
            	<input type="number" placeholder="0" name="quantity" min="1" step="1" className='shares-input'/>
          	</form>
		  </div>
		  
		  <div className='bs-containers'>
		  	<div className='bs-width-wrapper'>
          	<p>Estimated Cost</p>
		  	</div>
		  	<div>
		  	<p>placeholder </p>
		  	</div>
		  </div>
		  
		  <div>
          <button className='next' onClick={nextStep}>Next</button>
		  </div>
		  
		  <hr />		  
		  
		  <div className='bs-containers'>
		  	<div className='bs-width-wrapper'>
          	<p>Available Cash</p>
		  	</div>
		  	<div>
		  	<p>placeholder amt</p>
		  	</div>
		  </div>
		  
        </div>
      )}

      {currentState.action === "sell" && currentState.step === 1 && (
        <div className='bs-parent-container'>
		  
          <div className='bs-button-container'>
            <button onClick={buyState} className='buy-sell-button'>Buy</button>
            <button onClick={sellState} className='buy-sell-button'>Sell</button>
          </div>
		  
		  <div className='bs-containers'>
		  	<div className='bs-width-wrapper'>
		  	<p>Order Type</p>
		  	</div>
		  	<div>
		  	<p>Market Sell</p>
		  	</div>
		  </div>
		  
		  <div className='bs-containers'>
		  	<div className='bs-shares-wrapper'>
          	<label>Shares</label>
		  	</div>
          	<form>
            	<input type="number" placeholder="0" name="quantity" min="1" step="1" className='shares-input'/>
          	</form>
		  </div>
		  
		  <div className='bs-containers'>
		  	<div className='bs-width-wrapper'>
          	<p>Estimated Value</p>
		  	</div>
		  	<div>
		  	<p>placeholder amount</p>
		  	</div>
		  </div>
		  
		  <div>
          <button className='next' onClick={nextStep}>Next</button>
		  </div>
		  
		  <hr />		  
		 
		  <div className='bs-containers'>
		  	<div className='bs-width-wrapper'>
          	<p>Available Shares</p>
		  	</div>
		  	<div>
		  	<p>placeholder amt</p>
		  	</div>
		  </div>
		  
        </div>
      )}

      {currentState.action === "buy" && currentState.step === 2 && (
        <div className='bs-parent-container-two'>
		  
		  <div>
          <button onClick={prevStep}>back</button>
		  </div>
		  
		  <div className='bs-containers'>
		  	<div className='bs-width-wrapper'>
		  	<p>Order Type</p>
		  	</div>
		  	<div>
		  	<p>Market Buy</p>
		  	</div>
		  </div>
		  
		  <div className='bs-containers'>
		  	<div className='bs-width-wrapper'>
		  	<p>Quantity</p>
		  	</div>
		  	<div>
		  	<p>placeholder</p>
		  	</div>
		  </div>
		  
		  <div className='bs-containers'>
		  	<div className='bs-width-wrapper'>
		  	<p>Cost</p>
		  	</div>
		  	<div>
		  	<p>placeholder</p>
		  	</div>
		  </div>
		  
		  <div>
          <button className='next' onClick={nextStep}>Submit Order</button>
		  </div>
		  
        </div>
      )}

      {currentState.action === "sell" && currentState.step === 2 && (
        <div className='bs-parent-container-two'>
		  
		  <div>
          <button onClick={prevStep}>back</button>
		  </div>
		  
		  <div className='bs-containers'>
		  	<div className='bs-width-wrapper'>
		  	<p>Order Type</p>
		  	</div>
		  	<div>
		  	<p>Market Sell</p>
		  	</div>
		  </div>
		  
		  <div className='bs-containers'>
		  	<div className='bs-width-wrapper'>
		  	<p>Quantity</p>
		  	</div>
		  	<div>
		  	<p>placeholder</p>
		  	</div>
		  </div>
		  
		  <div className='bs-containers'>
		  	<div className='bs-width-wrapper'>
		  	<p>Value</p>
		  	</div>
		  	<div>
		  	<p>placeholder</p>
		  	</div>
		  </div>
		  
		  <div>
          <button className='next' onClick={nextStep}>Submit Order</button>
		  </div>
		  
        </div>
      )}

      {currentState.action === "sell" && currentState.step === 3 && (
        <div>
          <h2>Order Submitted!</h2>
          <p> Submitted</p>
          <p> order type</p>
          <p> Shares </p>
          <p> Value</p>
          <button onClick={buyState}>Done</button>
        </div>
      )}

      {currentState.action === "buy" && currentState.step === 3 && (
        <div>
          <h2>Order Submitted!</h2>
          <p> Submitted</p>
          <p> order type</p>
          <p> Shares </p>
          <p> Cost</p>
          <button onClick={buyState}>Done</button>
        </div>
      )}
    </>
  );
};

export default BuySell;
